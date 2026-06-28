# Superset has no native Cassandra connector, so we query it through PrestoDB.
# Talking to Presto needs the `presto://` SQLAlchemy dialect, which ships in
# PyHive -- not in the stock Superset image. This thin layer adds it.
FROM apache/superset:3.1.3

USER root
# pyhive[presto] -> the `presto://` dialect; requests is its HTTP transport.
RUN pip install --no-cache-dir "pyhive[presto]==0.7.0" "requests>=2.31"
# Bootstrap script (db upgrade + admin + init + serve); see compose `command`.
COPY superset-bootstrap.sh /app/superset-bootstrap.sh
RUN chmod +x /app/superset-bootstrap.sh
USER superset
