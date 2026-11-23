# Tech.Dropout: সার্ভার ডিপ্লয় আর অ্যাপ রিলিজ

এই গাইড একটা VPS-এ (Ubuntu 24.04, কমপক্ষে 2 GB RAM) পুরো সার্ভার চালু করা আর Play Store-এ অ্যাপ তোলার ধাপগুলো দেখায়।

## ১. সার্ভার কেনা আর DNS

1. যেকোনো VPS নিন (DigitalOcean, Vultr, Hetzner বা দেশি কোনো হোস্ট)। Ubuntu 24.04 বেছে নিন।
2. ডোমেইনের DNS প্যানেলে দুটো **A record** দিন, দুটোই সার্ভারের IP-তে:
   - `api.tech.dropout.it`
   - `tech.dropout.it` (আর চাইলে `www.tech.dropout.it`)

## ২. সার্ভারে Docker বসানো

```bash
ssh root@SERVER_IP
curl -fsSL https://get.docker.com | sh
git clone https://github.com/rahianalam/tech.dropoutit.git
cd tech.dropoutit
```

## ৩. গোপন তথ্য (`backend/.env`)

```bash
cp backend/.env.example backend/.env
nano backend/.env
```

যা বদলাতে হবে:

| নাম | কী দেবেন |
|---|---|
| `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `MEDIA_SIGNING_KEY`, `FILE_SIGNING_KEY` | প্রতিটার জন্য আলাদা লম্বা র‍্যান্ডম লেখা: `openssl rand -hex 32` |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | আপনার অ্যাডমিন লগইন |
| `PUBLIC_API_URL` | `https://api.tech.dropout.it/api/v1` |
| `PAYMENT_GATEWAY` | `sslcommerz` |
| `SSLCZ_BASE_URL` | প্রথমে `https://sandbox.sslcommerz.com`, লাইভ হলে `https://securepay.sslcommerz.com` |
| `SSLCZ_STORE_ID`, `SSLCZ_STORE_PASSWORD` | SSLCommerz থেকে পাওয়া |
| `FIREBASE_SERVICE_ACCOUNT` | পুশ নোটিফিকেশনের জন্য (নিচে ৬ নম্বর ধাপ) |
| `SUPPORT_EMAIL` | প্রাইভেসি পেজে দেখানো যোগাযোগের ইমেইল, যেমন `support@tech.dropout.it` |

`DATABASE_URL` আর `UPLOAD_DIR` Docker নিজেই ঠিক করে দেয়, বদলানোর দরকার নেই।

এই ফাইল কখনো GitHub-এ বা চ্যাটে দেবেন না।

## ৪. চালু করা

```bash
export POSTGRES_PASSWORD=$(openssl rand -hex 24)
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" > .env     # docker compose এটা পড়ে নেয়
docker compose up -d --build
docker compose exec api node dist/seed/seed.js         # প্রথম অ্যাডমিন তৈরি
```

যাচাই করুন:
- https://api.tech.dropout.it/health → `{"ok":true}`
- https://tech.dropout.it/privacy → প্রাইভেসি পলিসি

HTTPS সার্টিফিকেট Caddy নিজে নেয় আর নবায়ন করে।

### SSLCommerz প্যানেলে
IPN URL দিন: `https://api.tech.dropout.it/api/v1/payments/sslcommerz/ipn`

### আপডেট করা
```bash
cd tech.dropoutit && git pull && docker compose up -d --build
```
ডাটাবেস মাইগ্রেশন অ্যাপ চালুর সময় নিজে চলে।

### ব্যাকআপ (প্রতিদিন)
```bash
crontab -e
# প্রতিদিন রাত ৩টায় ডাটাবেস আর CV ফাইলের ব্যাকআপ, ১৪ দিনের পুরনো মুছে যায়
0 3 * * * cd /root/tech.dropoutit && mkdir -p backups && docker compose exec -T db pg_dump -U techdropout techdropout | gzip > backups/db-$(date +\%F).sql.gz && docker run --rm -v techdropoutit_uploads:/u -v $PWD/backups:/b alpine tar czf /b/uploads-$(date +\%F).tgz -C /u . && find backups -mtime +14 -delete
```
মাঝে মাঝে `backups` ফোল্ডারটা সার্ভারের বাইরে (Google Drive ইত্যাদিতে) কপি করে রাখুন।

### ওয়েব ভার্সন (ঐচ্ছিক)
অ্যাপের ওয়েব ভার্সন (অ্যাডমিন প্যানেল সহ) `tech.dropout.it`-এ দেখাতে:
```bash
cd app && flutter build web --release --dart-define=API_URL=https://api.tech.dropout.it/api/v1
cp -r build/web/* ../web/
```

## ৫. Android অ্যাপ: সাইনিং কী

Play Store-এ তোলার জন্য একটা **upload key** লাগে। নিজের কম্পিউটারে একবার বানান:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

এই ফাইল আর পাসওয়ার্ড হারালে অ্যাপ আপডেট দেওয়া কঠিন হয়ে যায়, তাই নিরাপদ জায়গায় দুই কপি রাখুন।

GitHub রিপোতে **Settings → Secrets and variables → Actions**-এ এই চারটা secret দিন:

| Secret | মান |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` কমান্ডের আউটপুট |
| `ANDROID_KEYSTORE_PASSWORD` | keystore পাসওয়ার্ড |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key পাসওয়ার্ড |

এরপর GitHub-এর **Actions → app** থেকে প্রতিবার Play Store-এর জন্য সাইন করা `.aab` ফাইল পাবেন। প্রতিটা PR-এ ফোনে ইনস্টল করার মতো একটা `.apk`-ও তৈরি হয় (Artifacts অংশে)।

## ৬. পুশ নোটিফিকেশন (Firebase)

1. https://console.firebase.google.com → নতুন প্রজেক্ট।
2. **Add app → Android**, প্যাকেজ নাম `it.dropout.tech`।
3. **Project settings → Service accounts → Generate new private key**। যে JSON ফাইল পাবেন সেটা `base64 -w0 file.json` করে `backend/.env`-এ `FIREBASE_SERVICE_ACCOUNT=` হিসেবে দিন।
4. **Project settings → General** থেকে এই চারটা মান GitHub-এ **Variables** হিসেবে দিন (এগুলো গোপন নয়): `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`, `FIREBASE_SENDER_ID`, `FIREBASE_ANDROID_APP_ID`।

Firebase না দিলেও অ্যাপ পুরোপুরি চলে। শুধু ফোনে পুশ আসবে না, অ্যাপের ভেতরের নোটিফিকেশন তালিকা ঠিকই কাজ করবে।

## ৭. Play Console

1. https://play.google.com/console → ডেভেলপার অ্যাকাউন্ট ($25, একবার)। নতুন ব্যক্তিগত অ্যাকাউন্ট হলে প্রোডাকশনে যাওয়ার আগে ১২ জন টেস্টার দিয়ে ১৪ দিন **closed testing** লাগতে পারে।
2. **Create app** → নাম "Tech.Dropout", ভাষা বাংলা।
3. যা লাগবে:
   - Privacy policy URL: `https://tech.dropout.it/privacy`
   - Account deletion URL: `https://tech.dropout.it/delete-account`
   - অ্যাপ আইকন 512×512 (`app/assets/icon/icon.png` থেকে), ফিচার গ্রাফিক 1024×500, অন্তত ২টা ফোন স্ক্রিনশট
   - Data safety ফর্ম: নাম, ইমেইল/ফোন, পেমেন্টের ইতিহাস, ফাইল (CV) সংগ্রহ করা হয়; এনক্রিপ্ট করে পাঠানো হয়; ইউজার ডিলিট করতে পারে
   - Content rating প্রশ্নাবলী, Target audience (১৮+ বা ১৩+)
4. **Testing → Internal testing**-এ প্রথম `.aab` আপলোড করে নিজের ফোনে দেখুন।

> **পেমেন্টের নিয়ম (সিদ্ধান্ত হয়ে গেছে):** Play Store আর App Store-এর অ্যাপে রেকর্ডেড কোর্স কেনা যায় না। স্টোর বিল্ডে (`STORE_BUILD=true`, CI নিজে দেয়) পেইড কোর্সের দাম আর কেনার বোতাম লুকানো থাকে, শুধু "প্রিমিয়াম কোর্স" লেখা দেখায়। শিক্ষার্থী কোর্স কেনে ওয়েবসাইটে (tech.dropout.it), তারপর একই অ্যাকাউন্ট দিয়ে অ্যাপে শেখে। অ্যাপের ভেতরে ওয়েবসাইটে কেনার লিংক দেওয়া হয়নি, কারণ স্টোরের নিয়মে সেটাও সাধারণত নিষেধ। ফ্রি কোর্স আর লাইভ ১:১ সেশনের পেমেন্ট (SSLCommerz) অ্যাপেই চলে।

## ৮. iOS (পরে)

Apple Developer অ্যাকাউন্ট ($99/বছর) আর একটা Mac লাগবে। বান্ডল আইডি `it.dropout.tech` সেট করা আছে। Apple-এর নিয়মও একই রকম: ডিজিটাল কোর্স বিক্রিতে In-App Purchase লাগে।
