import spacy
import requests
import tempfile
import os
from flask import Flask, request, jsonify
from geopy.geocoders import Nominatim
from geopy.exc import GeocoderTimedOut, GeocoderUnavailable

# --- NEW IMPORTS for Pillow ---
from PIL import Image, ExifTags
from io import BytesIO

# --- Configuration & Model Loading ---

print("Loading models... This may take a moment.")
# Load the lightweight spaCy model ONCE on startup
try:
    nlp = spacy.load("en_core_web_sm")
    print("spaCy 'en_core_web_sm' model loaded.")
except IOError:
    print("Error: spaCy model 'en_core_web_sm' not found.")
    print("Please run: python -m spacy download en_core_web_sm")
    exit(1)

# Initialize the Nominatim geocoder
# IMPORTANT: Provide a unique user_agent for their terms of service
geolocator = Nominatim(user_agent="my_hackathon_app_v1")

# Initialize Flask app
app = Flask(__name__)

# --- Helper Function for Pillow GPS ---
def dms_to_dd(dms, ref):
    """Converts DMS (Degrees, Minutes, Seconds) tuple to Decimal Degrees"""
    try:
        # dms is a tuple of tuples: ((deg, 1), (min, 1), (sec, 100))
        degrees = dms[0][0] / dms[0][1]
        minutes = dms[1][0] / dms[1][1]
        seconds = dms[2][0] / dms[2][1]
        
        dd = degrees + (minutes / 60.0) + (seconds / 3600.0)
        
        if ref in ['S', 'W']:
            dd = -dd
        return dd
    except Exception as e:
        print(f"Error converting DMS to DD: {e}")
        return None

# --- 1. NER Agent (/ner) ---
@app.route('/ner', methods=['POST'])
def extract_ner():
    """
    Extracts locations from a block of text.
    Expects JSON: {"text": "..."}
    Returns JSON: {"locations": ["...", "..."]}
    """
    data = request.json
    if not data or 'text' not in data:
        return jsonify({"error": "Missing 'text' in JSON body"}), 400

    text = data['text']
    doc = nlp(text)
    
    # Filter for Geopolitical Entities (GPE) and Locations (LOC)
    locations = [ent.text for ent in doc.ents if ent.label_ in ("GPE", "LOC")]
    
    # Deduplicate
    unique_locations = list(set(locations))
    
    print(f"NER found: {unique_locations}")
    return jsonify({"locations": unique_locations})

# --- 2. Metadata Agent (/exif) ---
@app.route('/exif', methods=['POST'])
def extract_exif():
    """
    Downloads an image from a URL and extracts GPS metadata using Pillow.
    Expects JSON: {"image_url": "..."}
    Returns JSON: {"gps": {"lat": ..., "lon": ...}} or {"gps": null}
    """
    data = request.json
    if not data or 'image_url' not in data:
        return jsonify({"error": "Missing 'image_url' in JSON body"}), 400

    image_url = data['image_url']
    
    try:
        response = requests.get(image_url, timeout=10)
        response.raise_for_status()
        
        # Read image from in-memory bytes
        img_bytes = BytesIO(response.content)
        img = Image.open(img_bytes)
        
        # Get EXIF data
        exif_data_raw = img._getexif()
        
        if not exif_data_raw:
            print("No EXIF data found.")
            return jsonify({"gps": None})

        # --- Parse EXIF data using Pillow ---
        
        # Find the tag ID for GPSInfo
        gps_info_tag_id = None
        for tag, name in ExifTags.TAGS.items():
            if name == 'GPSInfo':
                gps_info_tag_id = tag
                break
        
        if not gps_info_tag_id or gps_info_tag_id not in exif_data_raw:
            print("No GPSInfo tag found in EXIF data.")
            return jsonify({"gps": None})

        # Get the raw GPS data sub-dictionary
        gps_data_raw = exif_data_raw[gps_info_tag_id]
        
        # Map numerical GPS tags to human-readable names
        gps_data = {}
        for tag_id, value in gps_data_raw.items():
            tag_name = ExifTags.GPSTAGS.get(tag_id)
            if tag_name:
                gps_data[tag_name] = value

        # Extract the specific values needed
        lat_dms = gps_data.get('GPSLatitude')
        lat_ref = gps_data.get('GPSLatitudeRef')
        lon_dms = gps_data.get('GPSLongitude')
        lon_ref = gps_data.get('GPSLongitudeRef')

        if lat_dms and lat_ref and lon_dms and lon_ref:
            # Convert from DMS to Decimal Degrees
            final_lat = dms_to_dd(lat_dms, lat_ref)
            final_lon = dms_to_dd(lon_dms, lon_ref)
            
            if final_lat is not None and final_lon is not None:
                print(f"Pillow EXIF GPS found: ({final_lat}, {final_lon})")
                return jsonify({"gps": {"lat": final_lat, "lon": final_lon}})
            else:
                print("Failed to parse DMS GPS data.")
                return jsonify({"gps": None, "error": "Failed to parse DMS GPS data"})
        else:
            print("GPS tags (Lat/Lon/Ref) missing from GPSInfo.")
            return jsonify({"gps": None})

    except requests.exceptions.RequestException as e:
        print(f"Error downloading image: {e}")
        return jsonify({"error": f"Failed to download image: {e}"}), 500
    except Exception as e:
        print(f"Error processing EXIF with Pillow: {e}")
        return jsonify({"error": f"Error processing EXIF: {e}"}), 500

# --- 3. GIS Agent (/gis) ---
@app.route('/gis', methods=['POST'])
def perform_gis_lookup():
    """
    Uses Geopy to turn a location name into coordinates.
    Expects JSON: {"location_name": "..."}
    Returns JSON: {"results": [{"address": "...", "lat": ..., "lon": ...}, ...]}
    """
    data = request.json
    if not data or 'location_name' not in data:
        return jsonify({"error": "Missing 'location_name' in JSON body"}), 400
    
    location_name = data['location_name']
    
    try:
        locations = geolocator.geocode(location_name, exactly_one=False, limit=3)
        if not locations:
            print(f"GIS: No results for '{location_name}'")
            return jsonify({"results": []})
            
        results = [
            {"address": loc.address, "lat": loc.latitude, "lon": loc.longitude}
            for loc in locations
        ]
        print(f"GIS results for '{location_name}': {results}")
        return jsonify({"results": results})
        
    except (GeocoderTimedOut, GeocoderUnavailable) as e:
        print(f"GIS service error: {e}")
        return jsonify({"error": f"Geocoding service unavailable: {e}"}), 503

# --- Run the Server ---
if __name__ == '__main__':
    print("Starting AI Agent Server on http://localhost:5001")
    app.run(port=5001, debug=True)
