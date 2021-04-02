FROM python:3.8
# PYTHONUNBUFFERED variable is used for non-buffered stdout
ENV PYTHONUNBUFFERED=1

# changing our working directory to be /opt
WORKDIR /opt

# copying and installing python requirements
COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt

# copying the whole django application
COPY xkcd_app/ .

# exposing our django port: 8000
EXPOSE 8000

# serving django with gunicorn on port 8000 (1 worker, timeout of 5 secs)
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--timeout", "5", "xkcd_app.wsgi"]