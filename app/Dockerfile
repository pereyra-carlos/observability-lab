FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
COPY --from=build /install /usr/local
WORKDIR /app
COPY vantia ./vantia
COPY main.py .
RUN useradd -u 1000 -m vantia
USER 1000
CMD ["python", "main.py"]
