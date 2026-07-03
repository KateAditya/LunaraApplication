# Implementation Notes - Enhanced Database Schema

## Configuration Decisions

### ✅ Photo Storage: Local Files
- **Choice**: Store files in `uploads/` directory
- **Database**: Store relative file paths
- **Structure**:
  ```
  uploads/
    users/{user_id}/profile/
    users/{user_id}/gallery/
    venues/{venue_id}/cover/
    venues/{venue_id}/gallery/
    venues/{venue_id}/events/
  ```
- **Future**: Can migrate to cloud storage (S3/Cloudinary) without changing models

### ✅ Authentication: Email-First Approach
- **Active Now**: Email verification workflow
- **Deferred**: SMS/OTP verification (models created, not in use)
- **Reason**: Simplifies initial launch, SMS integration later

---

## What's Currently Active

### Authentication Features
1. ✅ **User Registration** - Basic account creation
2. ✅ **Email Verification** - 24-hour token workflow
3. ✅ **Password Reset** - 15-minute token workflow
4. ✅ **Login** - Email/password authentication
5. ⏳ **Phone OTP** - Model ready, not implemented yet

### User Profile Features
1. ✅ **Extended Profiles** - Bio, occupation, social links
2. ✅ **Photo Upload** - Local file storage
3. ✅ **Interests** - Categorized hobbies
4. ✅ **Preferences** - Vibe matching settings

### Social Features
1. ✅ **Vibe Matching** - Algorithm ready
2. ✅ **Connections** - Friend requests

### Venue Features
1. ✅ **Photo Management** - Categorized images
2. ✅ **Basic Info** - Name, location, capacity

---

## Next Steps for Phase 3

### Immediate Priority
1. **File Upload Middleware**
   - Install Multer: `npm install multer @types/multer`
   - Configure storage path
   - Add file validation (size, type)
   - Implement upload endpoints

2. **Email Service**
   - Choose provider (Nodemailer for Gmail, or SendGrid)
   - Set up templates for verification & password reset
   - Test email delivery

3. **Authentication API**
   - POST `/api/auth/register` - Create account + send verification
   - POST `/api/auth/verify-email` - Verify token
   - POST `/api/auth/login` - JWT login
   - POST `/api/auth/forgot-password` - Send reset email
   - POST `/api/auth/reset-password` - Complete reset

4. **Profile API**
   - GET/PATCH `/api/profile` - View/update profile
   - POST `/api/profile/photos` - Upload photos
   - GET/DELETE `/api/profile/photos/:id` - Manage photos
   - POST `/api/profile/interests` - Add interests
   - PATCH `/api/profile/preferences` - Vibe settings

5. **Matching API**
   - GET `/api/match/find` - Get compatible users
   - POST `/api/match/connect` - Accept match
   - GET `/api/match/suggestions` - Recommended matches

### Future Enhancements
1. **SMS Integration** (Phase 4)
   - Choose provider (MSG91 for India)
   - Implement OTP endpoints
   - Add phone verification to registration

2. **Cloud Storage Migration** (Phase 5)
   - Set up S3/Cloudinary
   - Migrate existing files
   - Update upload logic

3. **Advanced Matching** (Phase 6)
   - Machine learning recommendations
   - Event-based matching
   - Location-based suggestions

---

## File Upload Implementation Guide

### Install Dependencies
```bash
npm install multer @types/multer sharp @types/sharp
```

### Create Upload Middleware
```typescript
// src/middleware/upload.ts
import multer from 'multer';
import path from 'path';
import fs from 'fs';

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const userId = req.user.id;
    const uploadPath = path.join('uploads', 'users', userId, 'gallery');
    fs.mkdirSync(uploadPath, { recursive: true });
    cb(null, uploadPath);
  },
  filename: (req, file, cb) => {
    const timestamp = Date.now();
    const ext = path.extname(file.originalname);
    cb(null, `${timestamp}${ext}`);
  }
});

const fileFilter = (req: any, file: any, cb: any) => {
  const allowedTypes = ['image/jpeg', 'image/png', 'image/webp'];
  if (allowedTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Invalid file type'), false);
  }
};

export const uploadUserPhoto = multer({
  storage,
  fileFilter,
  limits: { fileSize: 5 * 1024 * 1024 } // 5MB
});
```

### Photo Upload Endpoint
```typescript
// src/routes/profile.ts
router.post('/photos', 
  authenticate, 
  uploadUserPhoto.single('photo'),
  async (req, res) => {
    const photo = await UserPhoto.create({
      userId: req.user.id,
      filePath: req.file.path,
      fileSize: req.file.size,
      mimeType: req.file.mimetype,
    });
    res.json(photo);
  }
);
```

---

## Email Service Implementation

### Install Dependencies
```bash
npm install nodemailer @types/nodemailer
```

### Email Service
```typescript
// src/services/emailService.ts
import nodemailer from 'nodemailer';

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASSWORD
  }
});

export async function sendVerificationEmail(email: string, token: string) {
  const verificationUrl = `${process.env.FRONTEND_URL}/verify-email?token=${token}`;
  
  await transporter.sendMail({
    from: process.env.EMAIL_FROM,
    to: email,
    subject: 'Verify Your Lunara Account',
    html: `
      <h1>Welcome to Lunara!</h1>
      <p>Click the link below to verify your email:</p>
      <a href="${verificationUrl}">Verify Email</a>
      <p>This link expires in 24 hours.</p>
    `
  });
}
```

---

## Summary

✅ **Configuration locked in**: Local storage + Email verification  
✅ **Database ready**: 15 tables with all models  
✅ **Next phase**: API endpoints + File upload + Email service  
⏳ **Deferred**: SMS/OTP (ready when needed)  

**Ready to proceed with Phase 3: API Development!**
