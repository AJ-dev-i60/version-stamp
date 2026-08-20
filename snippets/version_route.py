# FastAPI / Starlette. Mount alongside your health endpoint.
# If the app has router-wide auth, exempt this route the same way the
# health endpoint is exempted.

from app.version import VERSION, COMMIT


@app.get("/version")
def version():
    return {"version": VERSION, "commit": COMMIT}
