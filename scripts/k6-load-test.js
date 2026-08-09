import http from 'k6/http';
import { sleep } from 'k6';

const TARGET_HOST = __ENV.TARGET_HOST || 'localhost';

export const options = {
  stages: [
    { duration: '30s', target: 20 },
    { duration: '1m', target: 100 },
    { duration: '30s', target: 0 },
  ],
};

export default function () {
  // פנייה לנתיב העומס בדימוי עומסי CPU אמיתיים לבדיקת ה-HPA
  http.get(`https://${TARGET_HOST}/api/stress`, {
    insecureSkipTLSVerify: true, // התעלמות מתעודת Self-Signed במבחן עומסים
  });
  sleep(0.1);
}