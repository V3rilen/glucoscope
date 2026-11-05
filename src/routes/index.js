import { Router } from 'express';
import { showHome, showHealth } from '../controllers/homeController.js';

const router = Router();

router.get('/', showHome);
router.get('/health', showHealth);

export default router;
