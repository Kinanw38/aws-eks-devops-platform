# Stage 1: התקנת תלויות (npm install)
FROM node:18-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

# Stage 2: אימג' סופי, קל משקל ומאובטח
FROM node:18-alpine
WORKDIR /app

# אבטחה: הרצה תחת משתמש ללא הרשאות root
USER node

# העתקת package.json והספריות המותקנות משלב הבנייה
COPY --chown=node:node package*.json ./
COPY --chown=node:node --from=builder /app/node_modules ./node_modules

# העתקת קוד האפליקציה והדשבורד
COPY --chown=node:node app.js ./app.js
COPY --chown=node:node index.html ./index.html

EXPOSE 8080
ENV PORT=8080

CMD ["node", "app.js"]