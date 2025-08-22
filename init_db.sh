#!/bin/bash

# 데이터베이스 초기화 스크립트
# PostgreSQL 컨테이너 시작 시 실행됨

set -e

echo "데이터베이스 초기화를 시작합니다..."

# # 환경 변수 설정 yaml 파일에서 설정된 환경 변수 사용
# # POSTGRES_DB,  데이터베이스 이름
# # POSTGRES_USER, 사용자
# # POSTGRES_PASSWORD 비번

# DB_NAME=${POSTGRES_DB:-smart_home}
# DB_USER=${POSTGRES_USER:-postgres}
# DB_PASSWORD=${POSTGRES_PASSWORD:-smart_home_pw} # 비밀번호 
# PG_SOCKET_DIR="/var/run/postgresql" # 로컬 소켓으로 자동연결

# # 데이터베이스 연결 대기 (로컬 소켓 우선)
# echo "PostgreSQL 서버 연결을 기다리는 중..."
# until pg_isready -q -U "$DB_USER"; do # pg_isready 명령어로 PostgreSQL 서버가 준비되었는지 확인
#     echo "PostgreSQL 서버가 준비되지 않았습니다. 5초 후 재시도..."
#     sleep 5
# done

# echo "PostgreSQL 서버에 연결되었습니다."

# -----------------------------------------------------------------------------
# 1. PostgreSQL 시스템 설정 적용 (ALTER SYSTEM)
echo "PostgreSQL 설정 적용 중"

# 연결 및 인증
psql -v ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET listen_addresses = '*';
    ALTER SYSTEM SET max_connections = 100;
EOSQL

# -- 메모리 설정 --
echo "  - 메모리 설정을 적용합니다..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET shared_buffers = '256MB';
    ALTER SYSTEM SET effective_cache_size = '1GB';
    ALTER SYSTEM SET work_mem = '4MB';
    ALTER SYSTEM SET maintenance_work_mem = '64MB';
EOSQL

# -- WAL 설정 --
echo "  - WAL 설정을 적용합니다..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET wal_buffers = '16MB';
    ALTER SYSTEM SET checkpoint_completion_target = 0.9;
    ALTER SYSTEM SET wal_writer_delay = '200ms';
EOSQL

# -- 로깅 설정 --
echo "  - 로깅 설정을 적용합니다..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET log_destination = 'stderr';
    ALTER SYSTEM SET logging_collector = 'on';
    ALTER SYSTEM SET log_directory = 'log';
    ALTER SYSTEM SET log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log';
    ALTER SYSTEM SET log_rotation_age = '1d';
    ALTER SYSTEM SET log_rotation_size = '100MB';
    ALTER SYSTEM SET log_min_duration_statement = '1000ms';
    ALTER SYSTEM SET log_checkpoints = 'on';
    ALTER SYSTEM SET log_connections = 'on';
    ALTER SYSTEM SET log_disconnections = 'on';
    ALTER SYSTEM SET log_lock_waits = 'on';
    ALTER SYSTEM SET log_temp_files = 0;
EOSQL

# -- 통계 설정 --
echo "  - 통계 설정을 적용합니다..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET track_activities = 'on';
    ALTER SYSTEM SET track_counts = 'on';
    ALTER SYSTEM SET track_io_timing = 'on';
    ALTER SYSTEM SET track_functions = 'all';
EOSQL

# -- 자동 통계 수집 (Autovacuum) --
echo "  - 자동 통계 수집(Autovacuum) 설정을 적용합니다..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET autovacuum = 'on';
    ALTER SYSTEM SET autovacuum_max_workers = 3;
    ALTER SYSTEM SET autovacuum_naptime = '1min';
EOSQL

# -- 쿼리 최적화 --
echo "  - 쿼리 최적화 설정을 적용합니다..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET random_page_cost = 1.1;
    ALTER SYSTEM SET effective_io_concurrency = 200;
EOSQL

# -- 타임존 및 보안 설정 --
echo "  - 타임존 및 보안 설정을 적용합니다..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET timezone = 'UTC';
    ALTER SYSTEM SET password_encryption = 'scram-sha-256';
EOSQL

# -- 확장 설정 --
echo "  - 확장(shared_preload_libraries) 설정을 적용합니다..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
EOSQL

echo "PostgreSQL 시스템 설정 성공"
echo "임시 서버가 종료되고 최종 서버가 실행되면 모든 설정이 최종 적용됩니다."

#------------------------------------------------------------------------------
# 데이터베이스 생성 (존재하지 않는 경우)
echo "데이터베이스 '$DB_NAME'을 확인/생성 중..."
psql -v ON_ERROR_STOP=1 \
    --username "$DB_USER" \
    --dbname "postgres" <<-EOSQL 
    SELECT 'CREATE DATABASE $DB_NAME'
    WHERE NOT EXISTS ( 
        SELECT FROM pg_database WHERE datname = '$DB_NAME'
        )\gexec
EOSQL

#------------------------------------------------------------------------------
# 스키마 파일들을 순서대로 실행
echo "스키마 파일들을 실행 중..."

# 1. 사용자 스키마
echo "사용자 테이블 생성 중..."
psql -v ON_ERROR_STOP=1 \
    --username "$DB_USER" \
    --dbname "$DB_NAME" \
    -f /docker-entrypoint-initdb.d/schemas/user.sql

# 2. 기기 스키마
echo "기기 테이블 생성 중..."
psql -v ON_ERROR_STOP=1 \
    --username "$DB_USER" \
    --dbname "$DB_NAME" \
    -f /docker-entrypoint-initdb.d/schemas/device.sql

# 3. 자동화 스키마
echo "자동화 테이블 생성 중..."
psql -v ON_ERROR_STOP=1 \
    --username "$DB_USER" \
    --dbname "$DB_NAME" \
    -f /docker-entrypoint-initdb.d/schemas/automation.sql

# 4. 전력 로그 스키마
echo "전력 로그 테이블 생성 중..."
psql -v ON_ERROR_STOP=1 \
    --username "$DB_USER" \
    --dbname "$DB_NAME" \
    -f /docker-entrypoint-initdb.d/schemas/power_log.sql

#------------------------------------------------------------------------------
# 마이그레이션 파일들 실행 (있는 경우) 
if [ -d "/docker-entrypoint-initdb.d/migrations" ]; then
    echo "마이그레이션 파일들을 실행 중..."
    for migration in /docker-entrypoint-initdb.d/migrations/*.sql; do
        if [ -f "$migration" ]; then
            echo "마이그레이션 실행: $(basename $migration)"
            psql -v ON_ERROR_STOP=1 \
            --username "$DB_USER" \
            --dbname "$DB_NAME" \
            -f "$migration"
        fi
    done
fi

#------------------------------------------------------------------------------
# 초기 데이터 삽입 (있는 경우)
if [ -f "/docker-entrypoint-initdb.d/scheamas/seed.sql" ]; then
echo "초기 user 데이터를 삽입 중..."
    psql -v ON_ERROR_STOP=1 \
    --username "$DB_USER" \
    --dbname "$DB_NAME" \
    -f /docker-entrypoint-initdb.d/scheamas/seed.sql
fi

echo "데이터베이스 초기화가 완료되었습니다."

# 데이터베이스 상태 확인
echo "데이터베이스 테이블 목록:"
psql --username "$DB_USER" --dbname "$DB_NAME" -c "\dt"

echo "데이터베이스 초기화 스크립트가 성공적으로 완료되었습니다." 
