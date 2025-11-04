**Priority 1: Get the Core Pipeline Working**

1.  **Terminal 1: Run Ollama.**
    * Open the Ollama desktop app or run `ollama serve`.
    * You should have already run `ollama pull phi3:mini`.
    * *Leave this terminal running.*
    
#diff terinals

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
   #use debugged n8n workflow
    * Click "Execute Workflow" in the bottom right.
    * The "Manual Input (DEMO)" node will run, showing you the two input fields.
    * Click "Continue" to run the full workflow.

^all based on the setup.sh file

**Deployment for Demo:**
