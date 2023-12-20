import { createRoot } from "react-dom/client";
import { App } from "./old/App";

const container = document.getElementById("app-container");
const root = createRoot(container)
root.render(<App />);