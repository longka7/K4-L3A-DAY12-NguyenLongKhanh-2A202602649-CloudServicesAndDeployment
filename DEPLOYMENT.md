# Thông Tin Deploy — Checkpoint 5

> Điền file này sau khi deploy xong. `pytest tests/test_cp5.py` đọc file này
> để tìm địa chỉ service của bạn và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị API key vào đây.**
> Repo này công khai — dán khóa vào là mất khóa.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Nguyễn Long Khánh |
| Mã học viên | 2A202602649 |
| Repo | https://github.com/longka7/K4-L3A-DAY12-NguyenLongKhanh-2A202602649-CloudServicesAndDeployment |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://agent-production-acfb.up.railway.app |
| Platform | Railway (build từ `Dockerfile`, cấu hình `railway.toml`; service `agent` + Redis add-on trong project `day12-agent`) |
| Ngày deploy | 2026-09-28 |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | platform tự gán (log: `Uvicorn running on http://0.0.0.0:8080`) |
| `AGENT_API_KEY` | ✅ | khóa riêng cho cloud (khác khóa local), đặt qua `railway add --variables`, không nằm trong repo |
| `REDIS_URL` | ✅ | tham chiếu `${{Redis.REDIS_URL}}` tới Redis add-on của Railway (mạng nội bộ `redis.railway.internal:6379`) |
| `RATE_LIMIT_PER_MINUTE` | ✅ | 10 |
| `MONTHLY_BUDGET_USD` | ✅ | 10.0 |
| `LOG_LEVEL` | ✅ | INFO |

## Lệnh Kiểm Tra

Thay `<URL>` bằng Public URL ở trên:

```bash
# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i <URL>/health

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i <URL>/ready

# 3. Không có API key — mong đợi 401
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"Hello"}'

# 4. Có API key — mong đợi 200 kèm câu trả lời
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $AGENT_API_KEY" \
  -H "X-User-Id: sv-test" \
  -d '{"question":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST <URL>/ask \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $AGENT_API_KEY" \
    -H "X-User-Id: sv-test" \
    -d '{"question":"test"}'
done; echo
```

## Kết Quả Chạy Thật

Dán output của các lệnh trên vào đây:

Chạy ngày 2026-09-28 từ máy local, `<URL>` = Public URL ở trên, khóa lấy từ biến môi trường (không in ra):

```
$ curl -i <URL>/health
HTTP/2 200 
content-type: application/json
{"status":"ok","service":"day12-agent","version":"1.0.0"}

$ curl -i <URL>/ready
HTTP/2 200 
{"status":"ready","redis":true}

$ curl -i -X POST <URL>/ask (không có API key)
HTTP/2 401 
{"detail":"invalid or missing API key"}

$ curl -i -X POST <URL>/ask (có API key)
HTTP/2 200 
{"answer":"Câu hỏi hay. Deploy là gì thường được giải quyết bằng cách chuẩn hóa môi trường chạy: cùng một image chạy giống nhau ở laptop và trên cloud.","user_id":"sv-test","history_length":0,"cost_usd":2.145e-05,"tokens":{"in":3,"out":35}}

$ for i in $(seq 1 15); do ... /ask ... done
200 200 200 200 200 200 200 200 200 429 429 429 429 429 429
```

9 lần `200` rồi `429`: trước vòng lặp đã có 1 request của `sv-test` trong cùng cửa sổ 60 giây, nên tổng vẫn đúng 10 request/phút.

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên platform
- `screenshots/health.png` — kết quả gọi `/health` từ trình duyệt hoặc curl

---
