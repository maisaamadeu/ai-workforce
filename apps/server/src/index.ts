import { WebSocket, WebSocketServer } from "ws";
import { dataFile, openDatabase } from "./db.js";
import { createApp } from "./http.js";
import { setEventPublisher } from "./service.js";

const port = Number(process.env.AI_WORKFORCE_PORT ?? 47821);
const host = "127.0.0.1";
const db = openDatabase(dataFile());
const { server } = createApp(db);
const sockets = new WebSocketServer({ server, path: "/api/events" });

setEventPublisher((event) => {
  const payload = JSON.stringify(event);
  for (const client of sockets.clients) {
    if (client.readyState === WebSocket.OPEN) client.send(payload);
  }
});

server.listen(port, host, () => {
  process.stdout.write(`AI Workforce em http://${host}:${port}\n`);
});
