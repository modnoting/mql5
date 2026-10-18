# GIT WORKFLOW & AI PROMPT GUIDE — MQL5 REPOSITORY

คู่มือมาตรฐานและชุดคำสั่ง Prompt สำหรับการทำงานกับ Git และ GitHub ในโปรเจกต์ `mql5`

---

## 1. Master Prompt สำหรับการสั่ง AI จัดการ Git (Git Operations Prompt)

สามารถคัดลอกข้อความด้านล่างนี้ใช้สั่ง AI ในการจัดการ Git ในโปรเจกต์ได้ทันที:

```markdown
คุณคือ Git & DevOps Engineer สำหรับโปรเจกต์ MQL5 Forex Trading System
โปรดดำเนินการจัดการเวอร์ชันโค้ดใน Repository: https://github.com/modnoting/mql5 ตามมาตรฐานดังนี้:

1. Branching Strategy:
   - main: Production branch โค้ดที่เสถียรและพร้อมใช้งานจริง
   - dev: Development branch รวมฟีเจอร์ที่ผ่านการทดสอบเบื้องต้น
   - feature/<name>: พัฒนาฟังก์ชันหรือโมดูลใหม่
   - fix/<name>: แก้ไขบั๊กหรือปัญหาเร่งด่วน

2. Commit Convention (Conventional Commits):
   - feat: เพิ่มฟีเจอร์ หรือ EA/Indicator ใหม่ เช่น `feat(ea): add trailing stop logic`
   - fix: แก้ไขข้อผิดพลาดของโค้ด เช่น `fix(lot): resolve lot step rounding error`
   - refactor: ปรับปรุงโครงสร้างโค้ดโดยไม่เปลี่ยนผลลัพธ์
   - docs: ปรับปรุงเอกสาร เช่น `docs: update git workflow guide`
   - test: เพิ่มเติมหรือแก้ไขส่วนทดสอบ

3. Git Execution Rules:
   - ตรวจสอบ `git status` ก่อนทำงานเสมอ
   - อย่า commit ไฟล์ binary หรือ temporary (.ex5, .log, .tmp) ที่ไม่จำเป็น (ให้มีใน .gitignore)
   - แตก branch ย่อยจาก branch ล่าสุดเสมอ
   - เมื่อ commit และ push สำเร็จ ให้สร้าง Pull Request สรุปรายการเปลี่ยนแปลงอย่างละเอียด
```

---

## 2. Template Prompts สำหรับสั่งงานทั่วไป (Ready-to-Use Prompts)

### 2.1 สั่งสร้าง Branch และเริ่มงานใหม่
> "AI ช่วยสร้าง branch ใหม่ชื่อ `feature/<ชื่อฟีเจอร์>` แตกออกจาก `dev` และสลับไปที่ branch นั้น"

### 2.2 สั่ง Commit โค้ดพร้อมข้อความมาตรฐาน
> "AI ช่วยตรวจสอบไฟล์ที่มีการเปลี่ยนแปลง เพิ่มเข้า staging (`git add`) และ commit ด้วยข้อความ Conventional Commit: `feat/fix: <รายละเอียดภาษาอังกฤษหรือไทย>`"

### 2.3 สั่ง Push และเปิด Pull Request
> "AI ช่วย push branch `<ชื่อ branch>` ขึ้น `origin` และส่ง Pull Request ไปยัง branch `dev` (หรือ `main`) พร้อมสรุป Release Notes"

### 2.4 สั่ง Sync โค้ดล่าสุด
> "AI ช่วย fetch และ pull โค้ดล่าสุดจาก `origin/dev` มารวมเข้ากับ branch ปัจจุบัน และแจ้งหากมี merge conflict"

---

## 3. คำสั่ง Git มาตรฐานสำหรับผู้ใช้ (CLI Cheat Sheet)

### 3.1 ตั้งค่า Identity และ Remote Token
```bash
# กำหนดชื่อและอีเมลสำหรับ Commit
git config user.name "modnoting"
git config user.email "70569515+modnoting@users.noreply.github.com"

# เชื่อมต่อ Remote Repository ด้วย Personal Access Token (PAT)
git remote set-url origin https://<TOKEN>@github.com/modnoting/mql5.git
```

### 3.2 การแตก Branch และพัฒนาฟีเจอร์
```bash
# ตรวจสอบ branch ปัจจุบัน
git branch

# ดึงข้อมูลล่าสุดจาก remote
git fetch origin

# แตก branch ใหม่และสลับไปใช้งาน
git checkout -b feature/<branch-name>
```

### 3.3 การ Add, Commit และ Push
```bash
# ตรวจสอบสถานะไฟล์
git status

# เพิ่มไฟล์ทั้งหมด
git add .

# บันทึก Commit
git commit -m "feat: your descriptive message"

# Push ขึ้น Remote Repository
git push -u origin feature/<branch-name>
```

### 3.4 การสร้าง Pull Request ผ่าน GitHub REST API (PowerShell)
```powershell
$token = "<YOUR_GITHUB_TOKEN>"
$headers = @{
    "Authorization" = "Bearer $token"
    "Accept" = "application/vnd.github+json"
    "User-Agent" = "PowerShell"
}
$body = @{
    title = "feat: your feature title"
    head  = "feature/<branch-name>"
    base  = "dev"
    body  = "รายละเอียดการอัปเดตโค้ด"
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://api.github.com/repos/modnoting/mql5/pulls" -Headers $headers -Method Post -Body $body
```
