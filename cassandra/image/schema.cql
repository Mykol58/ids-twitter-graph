-- Schema baked into the image, applied once by the loader (/opt/ids/load.sh).
-- replication_factor = 3 to match the 3-node cluster: every row is kept on all
-- three nodes, so the cluster survives one node down at QUORUM.
CREATE KEYSPACE IF NOT EXISTS twitter
  WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 3 };

USE twitter;

CREATE TABLE IF NOT EXISTS edges (
    id             bigint PRIMARY KEY,
    follows        list<bigint>,
    is_followed_by list<bigint>
);
