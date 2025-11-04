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
