import uvicorn
from fastapi import FastAPI
# Import router từ file endpoints nằm trong thư mục con
from api.v1 import agent, admin, endpoints
from database.session import init_db

# Tự động tạo bảng DB khi khởi động
init_db()

# 1. Khởi tạo FastAPI App tại đây
app = FastAPI(title="Zero Trust Control Plane")

# 2. Gắn Router vào App
app.include_router(endpoints.router, prefix="/api/v1")

# Include Routers
app.include_router(agent.router, prefix="/api/v1/agent", tags=["Agent"])
app.include_router(admin.router, prefix="/api/v1/admin", tags=["Admin"])

# 3. Thêm endpoint kiểm tra sức khỏe đơn giản
@app.get("/")
def read_root():
    return {"message": "Welcome to the Zero Trust Control Plane API"}

@app.get("/health")
def health_check():
    return {"status": "ok", "service": "control-plane"}

# 4. Chạy ứng dụng với Uvicorn
if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)