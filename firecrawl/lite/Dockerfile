FROM python:3.12-slim

WORKDIR /app
RUN pip install --no-cache-dir \
    fastapi==0.115.12 \
    uvicorn[standard]==0.34.2 \
    httpx==0.28.1 \
    beautifulsoup4==4.13.4 \
    "lxml[html_clean]==5.4.0" \
    lxml_html_clean==0.4.2 \
    markdownify==1.1.0 \
    readability-lxml==0.8.1 \
    duckduckgo-search==8.0.2

COPY app.py .

ENV PORT=3002
EXPOSE 3002
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "3002"]
