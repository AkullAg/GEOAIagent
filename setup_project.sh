#!/bin/bash
echo "--- Starting Comprehensive Hackathon Project Setup (v2 with Pillow) ---"
echo "This script will create a new folder 'hackathon_geo_agent' with all necessary files."
echo

# --- Part 1: Manual Installs (Do These First!) ---
echo "--- Step 1: Manual Installs (Required) ---"
echo "Please ensure you have manually installed the following tools:"
echo
echo "1. n8n (Node.js required):"
echo "   Run: npm install -g n8n"
echo
echo "2. Ollama:"
echo "   - Go to https://ollama.com and download the app for your OS."
echo "   - After installing and running the Ollama app, run this in a terminal:"
echo "     ollama pull phi3:mini"
echo
echo "Press Enter to continue AFTER you have completed these manual installs..."
read -p "---"

# --- Part 2: Create Project Structure & Files ---
echo "--- Step 2: Creating Project Directory and Files ---"

PROJECT_DIR="hackathon_geo_agent"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo "Current directory: $(pwd)"
echo "Creating files..."

# Create requirements.txt (v2)
cat << 'EOF' > requirements.txt
# Lightweight web server for our AI agents
flask
# For making HTTP requests (to download images)
requests
# For lightweight, CPU-based NER
spacy
# For geocoding (turning 'Paris' into lat/lon)
geopy
# Geopandas for any GIS file ops (geopy is for API lookups)
geopandas
# Pure Python EXIF/Image library (replaces pyexiftool)
Pillow
# Optional: CrewAI, if you add the advanced module
# crewai
# crewai-tools
# langchain-community
EOF
echo "Created requirements.txt (using Pillow)"

# Create agent_services.py (v2)
cat << 'EOF' > agent_services.py
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
EOF
echo "Created agent_services.py (using Pillow)"

# Create workflow.json (No changes needed, but created for completeness)
cat << 'EOF' > workflow.json
{
  "nodes": [
    {
      "parameters": {},
      "name": "Start",
      "type": "n8n-nodes-base.start",
      "typeVersion": 1,
      "position": [
        240,
        300
      ]
    },
    {
      "parameters": {
        "fields": [
          {
            "name": "text_content",
            "type": "string",
            "default": "I took this photo on a trip to Paris.",
            "description": "Text from the social media post"
          },
          {
            "name": "image_url",
            "type": "string",
            "default": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a8/Tour_Eiffel_Wikimedia_Commons.jpg/800px-Tour_Eiffel_Wikimedia_Commons.jpg",
            "description": "A direct URL to an image"
          }
        ]
      },
      "name": "Manual Input (DEMO)",
      "type": "n8n-nodes-base.manualTrigger",
      "typeVersion": 1,
      "position": [
        460,
        300
      ]
    },
    {
      "parameters": {
        "url": "http://localhost:5001/ner",
        "options": {
          "body": "={{ {\"text\": $json.text_content} }}"
        }
      },
      "name": "Call NER Agent",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 3,
      "position": [
        920,
        180
      ],
      "credentials": {}
    },
    {
      "parameters": {
        "url": "http://localhost:5001/exif",
        "options": {
          "body": "={{ {\"image_url\": $json.image_url} }}"
        }
      },
      "name": "Call Exif Agent",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 3,
      "position": [
        920,
        420
      ],
      "credentials": {}
    },
    {
      "parameters": {
        "conditions": {
          "boolean": [
            {
              "value1": "={{ $json.text_content }}",
              "operation": "isNotEmpty"
            },
            {
              "value1": "={{ $json.image_url }}",
              "operation": "isNotEmpty"
            }
          ]
        },
        "combinator": "or"
      },
      "name": "Check Input",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [
        680,
        300
      ]
    },
    {
      "parameters": {
        "mode": "wait"
      },
      "name": "Merge Clues",
      "type": "n8n-nodes-base.merge",
      "typeVersion": 2,
      "position": [
        1140,
        300
      ]
    },
    {
      "parameters": {
        "conditions": {
          "boolean": [
            {
              "value1": "={{ $items('Call Exif Agent')[0].json.gps.lat }}",
              "operation": "isNotNull"
            }
          ]
        }
      },
      "name": "Found GPS?",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [
        1360,
        300
      ]
    },
    {
      "parameters": {
        "url": "http://localhost:5001/gis",
        "options": {
          "body": "={{ {\"location_name\": $items('Call NER Agent')[0].json.locations[0]} }}"
        }
      },
      "name": "Call GIS Agent",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 3,
      "position": [
        1560,
        420
      ],
      "notes": "For the hackathon, we just use the *first* location found by NER.\nA more advanced flow would loop over all of them.",
      "credentials": {}
    },
    {
      "parameters": {
        "conditions": {
          "boolean": [
            {
              "value1": "={{ $items('Call NER Agent')[0].json.locations.length }}",
              "operation": "larger",
              "value2": 0
            }
          ]
        }
      },
      "name": "Found NER?",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [
        1360,
        420
      ]
    },
    {
      "parameters": {
        "url": "http://localhost:11434/api/generate",
        "options": {
          "body": "={{ {\"model\": \"phi3:mini\", \"stream\": false, \"prompt\": $json.prompt} }}"
        }
      },
      "name": "Call Hyperstition Drive (Phi-3)",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 3,
      "position": [
        2280,
        300
      ],
      "credentials": {}
    },
    {
      "parameters": {
        "mode": "wait"
      },
      "name": "Merge Findings",
      "type": "n8n-nodes-base.merge",
      "typeVersion": 2,
      "position": [
        1820,
        300
      ]
    },
    {
      "parameters": {
        "data": "={{ $json.data }}\n",
        "options": {
          "mode": "json"
        }
      },
      "name": "Final Output",
      "type": "n8n-nodes-base.code",
      "typeVersion": 1,
      "position": [
        2500,
        300
      ],
      "notes": "This node just cleans up the final JSON for the demo"
    },
    {
      "parameters": {
        "keepOnlySet": true,
        "values": {
          "string": [
            {
              "name": "analysis_type",
              "value": "Direct GPS Match from Image"
            }
          ],
          "number": [
            {
              "name": "final_lat",
              "value": "={{ $items('Call Exif Agent')[0].json.gps.lat }}"
            },
            {
              "name": "final_lon",
              "value": "={{ $items('Call Exif Agent')[0].json.gps.lon }}"
            }
          ],
          "json": [
            {
              "name": "source_data",
              "value": "={{ $items('Call Exif Agent')[0].json.gps }}"
            }
          ]
        },
        "options": {}
      },
      "name": "Set: Direct Hit",
      "type": "n8n-nodes-base.set",
      "typeVersion": 2.1,
      "position": [
        1560,
        180
      ]
    },
    {
      "parameters": {
        "keepOnlySet": true,
        "values": {
          "string": [
            {
              "name": "analysis_type",
              "value": "Inferred from Text (GIS Lookup)"
            }
          ],
          "number": [
            {
              "name": "final_lat",
              "value": "={{ $items('Call GIS Agent')[0].json.results[0].lat }}"
            },
            {
              "name": "final_lon",
              "value": "={{ $items('Call GIS Agent')[0].json.results[0].lon }}"
            }
          ],
          "json": [
            {
              "name": "source_data",
              "value": "={{ $items('Call GIS Agent')[0].json.results[0] }}"
            }
          ]
        },
        "options": {}
      },
      "name": "Set: Text Hit",
      "type": "n8n-nodes-base.set",
      "typeVersion": 2.1,
      "position": [
        1560,
        560
      ]
    },
    {
      "parameters": {
        "keepOnlySet": true,
        "values": {
          "string": [
            {
              "name": "analysis_type",
              "value": "No Clues Found"
            }
          ],
          "json": [
            {
              "name": "source_data",
              "value": "{}"
            }
          ]
        },
        "options": {}
      },
      "name": "Set: No Hit",
      "type": "n8n-nodes-base.set",
      "typeVersion": 2.1,
      "position": [
        1360,
        560
      ]
    },
    {
      "parameters": {
        "values": {
          "string": [
            {
              "name": "prompt",
              "value": ""
            }
          ]
        },
        "options": {
          "import": "={{ {\n\"text\": $items('Manual Input (DEMO)')[0].json.text_content,\n\"image\": $items('Manual Input (DEMO)')[0].json.image_url,\n\"analysis\": $json.analysis_type,\n\"location\": $json.source_data.address || $json.analysis_type,\n\"lat\": $json.final_lat || null,\n\"lon\": $json.final_lon || null\n} }}\n"
        }
      },
      "name": "Build Phi-3 Prompt",
      "type": "n8n-nodes-base.set",
      "typeVersion": 2.1,
      "position": [
        2040,
        300
      ],
      "notes": "See prompts.md file for the template. You'll paste it into the 'prompt' value here."
    }
  ],
  "connections": {
    "Start": {
      "main": [
        [
          {
            "node": "Manual Input (DEMO)",
            "index": 0
          }
        ]
      ]
    },
    "Manual Input (DEMO)": {
      "main": [
        [
          {
            "node": "Check Input",
            "index": 0
          }
        ]
      ]
    },
    "Call NER Agent": {
      "main": [
        [
          {
            "node": "Merge Clues",
            "index": 0
          }
        ]
      ]
    },
    "Call Exif Agent": {
      "main": [
        [
          {
            "node": "Merge Clues",
            "index": 1
          }
        ]
      ]
    },
    "Check Input": {
      "main": [
        [
          {
            "node": "Call NER Agent",
            "index": 0
          }
        ],
        [
          {
            "node": "Call Exif Agent",
            "index": 0
          }
        ]
      ]
    },
    "Merge Clues": {
      "main": [
        [
          {
            "node": "Found GPS?",
            "index": 0
          }
        ]
      ]
    },
    "Found GPS?": {
      "main": [
        [
          {
            "node": "Set: Direct Hit",
            "index": 0
          }
        ],
        [
          {
            "node": "Found NER?",
            "index": 0
          }
        ]
      ]
    },
    "Call GIS Agent": {
      "main": [
        [
          {
            "node": "Set: Text Hit",
            "index": 0
          }
        ]
      ]
    },
    "Found NER?": {
      "main": [
        [
          {
            "node": "Call GIS Agent",
            "index": 0
          }
        ],
        [
          {
            "node": "Set: No Hit",
            "index": 0
          }
        ]
      ]
    },
    "Call Hyperstition Drive (Phi-3)": {
      "main": [
        [
          {
            "node": "Final Output",
            "index": 0
          }
        ]
      ]
    },
    "Merge Findings": {
      "main": [
        [
          {
            "node": "Build Phi-3 Prompt",
            "index": 0
          }
        ]
      ]
    },
    "Set: Direct Hit": {
      "main": [
        [
          {
            "node": "Merge Findings",
            "index": 0
          }
        ]
      ]
    },
    "Set: Text Hit": {
      "main": [
        [
          {
            "node": "Merge Findings",
            "index": 1
          }
        ]
      ]
    },
    "Set: No Hit": {
      "main": [
        [
          {
            "node": "Merge Findings",
            "index": 2
          }
        ]
      ]
    },
    "Build Phi-3 Prompt": {
      "main": [
        [
          {
            "node": "Call Hyperstition Drive (Phi-3)",
            "index": 0
          }
        ]
      ]
    }
  }
}
EOF
echo "Created workflow.json"

# Create prompts.md (No changes needed)
cat << 'EOF' > prompts.md
### System Prompt (Set in Ollama or n8n)

You are the "Hyperstition Drive," the creative AI core for a geo-location analysis system. Your purpose is NOT to state facts, but to weave a short, speculative, and imaginative narrative (1-2 paragraphs) based on the *implications* of the factual data you are given. Be poetic, slightly mysterious, and insightful.

---

### User Prompt (Paste this into the n8n "Build Phi-3 Prompt" node)

This is the template you'll use in n8n. The `{{ ... }}` syntax is for n8n expressions.

```
SYSTEM: You are the "Hyperstition Drive," a creative AI core. Your purpose is NOT to state facts, but to weave a short, speculative, and imaginative narrative (1-2 paragraphs) based on the *implications* of the factual data. Be poetic and mysterious.

USER:
**Factual Analysis Report:**
* **Input Text:** `{{ $items('Build Phi-3 Prompt')[0].json.text }}`
* **Image Provided:** `{{ $items('Build Phi-Impromptu')[0].json.image ? 'true' : 'false' }}`
* **Analysis Method:** `{{ $items('Build Phi-3 Prompt')[0].json.analysis }}`
* **Determined Location:** `{{ $items('Build Phi-3 Prompt')[0].json.location }}`
* **Coordinates:** `(Lat: {{ $items('Build Phi-3 Prompt')[0].json.lat }}, Lon: {{ $items('Build Phi-3 Prompt')[0].json.lon }})`

**Your Task:**
Generate the "Hyperstition Narrative" for this report. Do not repeat the facts. Speculate on the *feeling*, *meaning*, or *hidden story* behind this data point.

**Narrative:**
```

---
### Example 1: (Input with a Direct GPS Hit)

**Factual Analysis Report:**
* **Input Text:** `Best vacation ever!`
* **Image Provided:** `true`
* **Analysis Method:** `Direct GPS Match from Image`
* **Determined Location:** `Eiffel Tower, Paris, France`
* **Coordinates:** `(Lat: 48.8584, Lon: 2.2945)`

**Your Task:**
...

**Narrative:**
The data points to a precise pinprick on the globe, a signal beamed directly from the iron lattice. But the text is pure emotion. It's a memory crystallized—the feeling of "best" anchored to a specific set of coordinates. The machine sees the location, but the 'hyperstition' is in the human act of capturing a feeling and tagging it to a monolith, a moment made permanent in silicon and steel.

---
### Example 2: (Input with No Clues)

**Factual Analysis Report:**
* **Input Text:** `Thinking...`
* **Image Provided:** `false`
* **Analysis Method:** `No Clues Found`
* **Determined Location:** `null`
* **Coordinates:** `(Lat: null, Lon: null)`

**Your Task:**
...

**Narrative:**
This is a digital ghost. A thought untethered from geography, existing only in the non-space of the network. It's a statement of pure state, deliberately or accidentally scrubbed of 'where'. The absence of data becomes its own map—a map of introspection, a place the satellites can't see.
EOF
echo "Created prompts.md"

# Create hackathon_guide.md (v2 - Removed ExifTool)
cat << 'EOF' > hackathon_guide.md
**Priority 1: Get the Core Pipeline Working**

Your goal is a successful demo. Don't get lost in non-essential features.

**Step-by-Step "Wiring" Plan:**

1.  **Terminal 1: Run Ollama.**
    * Open the Ollama desktop app or run `ollama serve`.
    * You should have already run `ollama pull phi3:mini`.
    * *Leave this terminal running.*

2.  **Terminal 2: Run Your AI Agents.**
    * `source .venv/bin/activate` (if not already).
    * `python agent_services.py`
    * You should see `* Running on http://localhost:5001`.
    * *Leave this terminal running.*

3.  **Terminal 3: Run n8n.**
    * `n8n start`
    * This will open n8n in your browser (usually `http://localhost:5678`).
    * *Leave this terminal running.*

4.  **Browser (n8n Canvas):**
    * Create a new, blank workflow.
    * Open `workflow.json` in a text editor, copy its contents.
    * Paste the JSON directly onto the n8n canvas.
    * Open `prompts.md`, copy the **User Prompt** template (the part inside the ``` block).
    * In n8n, find the **"Build Phi-3 Prompt"** node, click it, and paste the prompt template into the `prompt` value field.
    * Click "Execute Workflow" in the bottom right.
    * The "Manual Input (DEMO)" node will run, showing you the two input fields.
    * Click "Continue" to run the full workflow.

**Testing and Debugging (The "Hackathon Loop"):**

* **Test Flask First:** Before you even use n8n, use a command line tool like `curl` to test your agents.
    * `curl -X POST -H "Content-Type: application/json" -d '{"text": "I am in Berlin"}' http://localhost:5001/ner`
    * If this works, your agent is good. If not, fix it in `agent_services.py`.
* **Debug n8n Visually:** n8n is amazing for debugging.
    * Run the workflow once.
    * Click on *any* node to see its "Input" and "Output" in the right-hand panel.
    * If the "Call NER Agent" node has an error, you can see the *exact* data it sent and the *exact* error it got back.
    * **"Pin" Data:** Right-click a node and "Pin" it. This locks its output, so you can re-run *only* the downstream nodes without having to call the APIs again. This is a massive time-saver.
* **Check Your Logs:** Your three terminals are your best friends.
    * The `agent_services.py` terminal will show `POST /ner` requests and any Python errors.
    * The `ollama serve` terminal will show requests to Phi-3.
    * The `n8n start` terminal will show n8n system errors.

**Deployment for Demo:**

* **DO NOT DEPLOY TO THE CLOUD.** It's a waste of time.
* Your demo is running all three terminals and the browser on your i7 laptop. This is the "local-first" deployment, and it's perfect for a hackathon.
* Have the n8n canvas visible. Click "Execute Workflow" live. Walk the judges through the flow as the green "success" checkmarks appear on each node.
* Show them the final output data in the "Final Output" node. This is a powerful and professional way to demo.
EOF
echo "Created hackathon_guide.md (Your runbook!)"

# --- Part 3: Setup Python Environment ---
echo "--- Step 3: Setting up Python Environment ---"
echo "Creating Python virtual environment in ./.venv ..."
python3 -m venv .venv
source .venv/bin/activate

echo "Installing Python dependencies from requirements.txt..."
pip install -r requirements.txt

echo "Downloading spaCy model 'en_core_web_sm'..."
python3 -m spacy download en_core_web_sm

echo
echo "--- ALL FILES CREATED AND PYTHON ENV READY! ---"
echo

# --- Part 4: How to Run ---
echo "--- FINAL: How to Run Your Project ---"
echo
echo "You are currently in: $(pwd)"
echo "From this directory, you need to run 3 commands in 3 separate terminals:"
echo
echo "--- Terminal 1: Start Ollama (if not already running) ---"
echo "(Run the Ollama App, or in a new terminal, type:)"
echo "ollama serve"
echo
echo "--- Terminal 2: Start Your AI Agent Server ---"
echo "(In a new terminal, run:)"
echo "source .venv/bin/activate"
echo "python agent_services.py"
echo "(Wait to see: * Running on http://localhost:5001)"
echo
echo "--- Terminal 3: Start n8n ---"
echo "(In a new terminal, run:)"
echo "n8n start"
echo "(This will open n8n in your browser at http://localhost:5678)"
echo
echo "--- In Your Browser (n8n): ---"
echo "1. Create a new workflow."
echo "2. Open the 'workflow.json' file (in this folder), copy ALL text."
echo "3. Paste the text onto the blank n8n canvas."
echo "4. Open the 'prompts.md' file, copy the 'User Prompt' template."
echo "5. In n8n, click the 'Build Phi-3 Prompt' node and paste the prompt into the 'prompt' field."
echo "6. Click 'Execute Workflow' (bottom right) and follow the demo!"
echo
echo "--- Hackathon Setup Complete! Good luck! ---"

