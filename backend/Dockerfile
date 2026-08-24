ARG PYTHON_BASE=python:3.11-slim-bookworm
ARG PIP_INDEX_URL=https://pypi.org/simple
FROM ${PYTHON_BASE} AS runtime
ARG PIP_INDEX_URL=https://pypi.org/simple
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN addgroup --system app && adduser --system --ingroup app app
COPY backend/requirements.txt requirements.txt
RUN python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" --upgrade wheel==0.46.2 setuptools \
    && python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" -r requirements.txt
COPY backend ./backend
# Use numeric IDs so Kubernetes can enforce runAsNonRoot without relying on
# image metadata from a remote registry.
USER 100:101
EXPOSE 8000
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
