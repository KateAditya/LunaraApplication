import { Router } from 'express';
import { updateProfileValidation, changePasswordValidation } from '../middleware/profileValidator';
import {
    updateProfile,
    changePassword,
    deletePhoto,
    setPrimaryPhoto,
} from '../controllers/profileController';
import mobileUserController from '../controllers/mobileUserController';
import { uploadTempPhotos } from '../middleware/upload';
import { authenticate } from '../middleware/auth';

const router = Router();

// Apply authentication middleware to all profile routes
router.use(authenticate);

// Update profile details
router.put('/update', updateProfileValidation, updateProfile);

// Change password
router.post('/change-password', changePasswordValidation, changePassword);

// Photo management
router.post('/photos', uploadTempPhotos.array('photos', 6), mobileUserController.uploadPhotos);
router.delete('/photos/:id', deletePhoto);
router.put('/photos/:id/primary', setPrimaryPhoto);

export default router;
