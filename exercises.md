# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng `> *Câu trả lời của bạn*` bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Nguyễn Long Khánh  Mã học viên: 2A202602649

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> Tình huống: lúc tạo service trên Railway/Render mình quên set `AGENT_API_KEY`. Nếu có mặc định `"changeme"`, app vẫn chạy, `/health` báo 200, deploy "xanh" — nhưng ai đọc được repo (public) đều biết khóa `changeme` và gọi `/ask` miễn phí, hóa đơn LLM tăng mà mình không hay. Không có mặc định thì container chết ngay lúc khởi động, platform báo deploy fail, mình thấy lỗi và set biến trước khi có người ngoài gọi vào.
>
> Quan sát thực tế: ban đầu `Settings` chỉ được đọc lười (lần đầu gọi `/ask`), nên chạy `docker run -e REDIS_URL=fake:// agent:multi` **không có key** container vẫn "healthy" suốt 3 phút — fail fast chưa hề xảy ra. Mình thêm `get_settings()` vào `lifespan` và lúc này container thoát ngay với `ValidationError: agent_api_key Field required` · `Application startup failed. Exiting.` (exit code 3).

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Dòng log thật (compose, user `sv-rl`):
>
> `{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T07:45:12.569036+00:00", "user_id": "sv-rl", "tokens_in": 302, "tokens_out": 43, "cost_usd": 7.11e-05}`
>
> Hai việc `print("đã trả lời xong")` không làm được: (1) **lọc/đếm theo trường** — ví dụ lọc `event=ask_completed AND user_id=sv-rl` để xem một user gọi bao nhiêu lần, hay đếm số dòng `level=error` trong 5 phút để bật cảnh báo; (2) **cộng dồn số liệu** — tổng `cost_usd` theo user/ngày, trung bình `tokens_in` (thấy rõ prompt phình ra theo lịch sử: 302 → 347 → 392 token qua 3 lượt) mà không phải viết regex bóc chữ.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ... MB |
| Multi-stage | ... MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

> | Bản | Dung lượng |
> |-----|-----------|
> | 1 stage (`Dockerfile.single`, base `python:3.11`) | **1,73 GB** |
> | Multi-stage (`Dockerfile`, base `python:3.11-slim`) | **311 MB** |
>
> (base `python:3.11-slim` riêng đã là 215 MB.) Phần chênh ~1,4 GB gồm: base image đầy đủ (Debian đầy đủ + gcc, make, header, git... để build package C — runtime không cần), thư viện test (`pytest`, `httpx`, `fakeredis`, `PyYAML` — bản multi-stage cắt phần `# Test` khỏi requirements trước khi cài), và build context copy bằng `COPY . .` (tests, file .md...). Stage runtime chỉ nhận `/opt/venv` + `app/` + `utils/`.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Sửa 1 ký tự trong `app/main.py` rồi build lại: các bước `FROM`, `WORKDIR`, `groupadd/useradd`, `COPY requirements.txt`, `RUN ... pip install` và `COPY --from=builder /opt/venv` đều **CACHED**; chỉ `COPY app/` và `COPY utils/` chạy lại → cả lần build mất **1 giây**. Lần build đầu, riêng bước `pip install` mất **77,9 giây**.
>
> Nếu đặt `COPY . .` trước `RUN pip install`: layer `COPY` đổi checksum vì main.py đổi → mọi layer sau nó, gồm `pip install`, mất cache → mỗi lần sửa code chờ lại ~78 giây tải lại thư viện (mạng mình chậm nên còn hay đứt giữa chừng).

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> Chuỗi sự kiện: (1) code có lỗ hổng, ví dụ deserialize/đọc file theo input người dùng hoặc thư viện dính RCE → kẻ tấn công chạy được lệnh trong process Python; (2) process chạy bằng **root** (uid 0) trong container; (3) container chia chung kernel với host — root trong container + một cấu hình lỏng (mount `docker.sock`, `--privileged`, volume host) hoặc một lỗ hổng kernel/runtime là thoát ra host với quyền root; kể cả không thoát được thì vẫn sửa được mọi file trong container, cài công cụ, đọc secret.
>
> `USER app` cắt chuỗi ở bước (2): kiểm tra thật `docker compose exec agent id` → `uid=10001(app) gid=10001(app)`. Lệnh bị chiếm quyền chỉ chạy dưới user không đặc quyền, không ghi được vào thư mục hệ thống, không có shell đăng nhập (`/usr/sbin/nologin`), nên bước leo thang lên root/host khó hơn nhiều.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> Tối đa **20 request trong 2 giây**. Cách đạt: gửi 10 request lúc 10:00:59 (vẫn trong "phút 10:00", đủ 10/10) → tới 10:01:00 bộ đếm reset → gửi tiếp 10 request lúc 10:01:00–10:01:01. Trong khoảng 2 giây có 20 request mà không vi phạm "10/phút".
>
> Sliding window đếm 60 giây **tính lùi từ bây giờ**, nên lúc 10:01:01 nó vẫn thấy 10 request của 10:00:59 và chặn. Thực tế gọi 15 lần liên tiếp: `200 ×10` rồi `429 ×5` (có header `Retry-After: 60`).

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> Rate limit giới hạn **số request trong một khoảng thời gian ngắn** (10/phút) — chống spam/tràn tải. Cost guard giới hạn **số tiền cộng dồn trong tháng** (10 USD/user) — chống cháy ngân sách. Một cái đếm lần gọi, một cái đếm chi phí.
>
> Rate limit cho qua nhưng cost guard chặn: user gửi đều 5 request/phút (dưới hạn mức) nhưng mỗi request kèm lịch sử dài/câu hỏi rất dài → vài ngày là tiêu hết 10 USD → `402`. Ngược lại: user mới, chưa tiêu gì (còn nguyên ngân sách) nhưng script bắn 50 request trong 10 giây → request thứ 11 bị `429`, dù tiền vẫn còn.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> Giả sử một endpoint duy nhất vừa là liveness vừa kiểm tra Redis:
> 1. Redis mất kết nối → cả 3 container cùng trả 503 trên endpoint đó.
> 2. Orchestrator thấy liveness fail đủ số lần (vd 3 lần × 10s) → coi cả 3 container là "chết" → **restart cả 3 cùng lúc**.
> 3. Trong lúc restart, request đang xử lý dở bị cắt, và không còn instance nào nhận traffic → toàn bộ service down, kể cả các request không cần Redis.
> 4. Container khởi động lại, Redis vẫn chưa về → health vẫn fail → vòng restart lặp lại (crash loop), khởi động lại còn tốn thêm thời gian.
> 5. Redis về sau 30s, nhưng cụm phải chờ lượt restart kế tiếp mới hồi phục → downtime dài hơn 30s.
>
> Tách ra: `/health` chỉ trả lời "process còn sống" (không gọi Redis) nên không ai bị restart; `/ready` trả 503 → load balancer tạm ngừng gửi traffic vào; Redis về → `/ready` 200 lại ngay, không restart container nào.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Chạy thật `AGENT_PORT_MAPPING=8000 docker compose --profile lb up -d --scale agent=3` (nginx round-robin), gọi 6 lần với `X-User-Id: sv-scale`: `history_length` = **0, 2, 4, 6, 8, 10**, trong khi log cho thấy request rơi đều vào `agent-1` ×2, `agent-2` ×2, `agent-3` ×2 — lịch sử vẫn liền mạch vì nằm trong Redis.
>
> Nếu lưu trong dict Python, mỗi container có dict riêng: lượt 1 vào agent-1 → 0; lượt 2 vào agent-2 → 0 (agent-2 chưa thấy gì); lượt 3 vào agent-3 → 0; lượt 4 quay lại agent-1 → 2... Con số sẽ nhảy lung tung kiểu 0, 0, 0, 2, 2, 2 và agent "mất trí nhớ" tùy request rơi vào đâu; restart một container là mất sạch phần lịch sử của nó.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> *Câu trả lời của bạn*
