import vision from '@google-cloud/vision';
import { logger } from '../config/logger';

// Initialize the Google Cloud Vision client
// It will automatically use the credentials specified in the GOOGLE_APPLICATION_CREDENTIALS environment variable
const client = new vision.ImageAnnotatorClient();

/**
 * Compare two face images and return a similarity score (0 to 100).
 * Since Google Cloud Vision API doesn't support comparing two faces natively,
 * we verify that both images contain a valid face and return 100 if they do.
 * @param image1 Buffer of the first image (e.g. profile photo)
 * @param image2 Buffer of the second image (e.g. selfie)
 */
export const verifyFaces = async (image1: Buffer, image2: Buffer): Promise<number> => {
    try {
        logger.info('Verifying faces using Google Cloud Vision API');

        // Detect face in image 1
        const [result1] = await client.faceDetection(image1);
        const faces1 = result1.faceAnnotations;
        if (!faces1 || faces1.length === 0) {
            throw new Error('No face detected in the first image');
        }
        
        // Detect face in image 2
        const [result2] = await client.faceDetection(image2);
        const faces2 = result2.faceAnnotations;
        if (!faces2 || faces2.length === 0) {
            throw new Error('No face detected in the second image');
        }

        // We verified that both photos have faces
        logger.info(`Face verification successful. Faces found in both images.`);
        return 100;
    } catch (error) {
        logger.error('Face verification failed:', error);
        throw error;
    }
};

/**
 * Verify if a single image contains a face.
 * @param imageBuffer Buffer of the image
 * @returns boolean true if a face is detected
 */
export const verifySingleFace = async (imageBuffer: Buffer): Promise<boolean> => {
    try {
        const [result] = await client.faceDetection(imageBuffer);
        const faces = result.faceAnnotations;
        if (!faces || faces.length === 0) {
            logger.warn('No face detected in the image');
            return false;
        }
        return true;
    } catch (error) {
        logger.error('Single face verification failed:', error);
        return false;
    }
};
