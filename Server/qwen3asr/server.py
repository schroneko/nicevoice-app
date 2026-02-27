import argparse
import base64
import json
import logging
import time

import numpy as np

logger = logging.getLogger("qwen3asr.server")


def create_app(model_name: str):
    from fastapi import FastAPI, WebSocket, WebSocketDisconnect
    from fastapi.responses import JSONResponse
    from mlx_qwen3_asr import Session

    logger.info("Loading model: %s", model_name)
    t0 = time.monotonic()

    def session_factory():
        return Session(model=model_name)

    warm = session_factory()
    logger.info("Model loaded in %.1fs", time.monotonic() - t0)
    del warm

    app = FastAPI(title="qwen3asr realtime server")

    @app.get("/health")
    async def health():
        return JSONResponse({"status": "ok"})

    @app.websocket("/v1/realtime")
    async def realtime(ws: WebSocket):
        await ws.accept()
        logger.info("WebSocket connected")

        session = session_factory()
        session.init_streaming(chunk_sec=2.0)
        full_text = ""

        await ws.send_json({"type": "session.created"})

        try:
            while True:
                raw = await ws.receive_text()
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    await ws.send_json({"type": "error", "message": "Invalid JSON"})
                    continue

                msg_type = msg.get("type", "")

                if msg_type == "session.update":
                    await ws.send_json({"type": "session.updated"})

                elif msg_type == "input_audio_buffer.append":
                    audio_b64 = msg.get("audio", "")
                    if not audio_b64:
                        continue

                    pcm16_bytes = base64.b64decode(audio_b64)
                    pcm16 = np.frombuffer(pcm16_bytes, dtype=np.int16)
                    audio_f32 = pcm16.astype(np.float32) / 32768.0

                    delta = session.feed_audio(audio_f32)
                    if delta:
                        full_text += delta
                        await ws.send_json(
                            {
                                "type": "response.audio_transcript.delta",
                                "delta": delta,
                            }
                        )

                elif msg_type == "input_audio_buffer.commit":
                    is_final = msg.get("final", False)
                    if is_final:
                        delta = session.finish_streaming()
                        if delta:
                            full_text += delta
                            await ws.send_json(
                                {
                                    "type": "response.audio_transcript.delta",
                                    "delta": delta,
                                }
                            )
                        await ws.send_json(
                            {
                                "type": "response.audio_transcript.done",
                                "text": full_text,
                            }
                        )
                        session.init_streaming(chunk_sec=2.0)
                        full_text = ""

        except WebSocketDisconnect:
            logger.info("WebSocket disconnected")
        except Exception:
            logger.exception("WebSocket error")

    return app


def main():
    parser = argparse.ArgumentParser(description="qwen3asr realtime WebSocket server")
    parser.add_argument(
        "--model",
        default="schroneko/Qwen3-ASR-1.7B-MLX-4bit",
        help="Model path or HF model ID",
    )
    parser.add_argument("--port", type=int, default=8001, help="Port to listen on")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind to")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )

    import uvicorn

    app = create_app(args.model)
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
