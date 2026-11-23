# ফাইল ও ভিডিও স্টোরেজ

সব আপলোড (CV, কোম্পানির লোগো, কোর্সের ছবি, লেসন ভিডিও) একটা জায়গা দিয়ে যায়: `backend/src/storage/storage.ts`-এর `StorageDriver`। বাকি কোড শুধু এই ইন্টারফেস চেনে, তাই স্টোরেজ বদলাতে একটা ক্লাস লিখে `.env`-এ একটা লাইন বদলালেই হয়।

## এখন যা চলছে: `STORAGE_DRIVER=local`

- ফাইল থাকে সার্ভারের ডিস্কে, Docker ভলিউম `uploads`-এ (`/data/uploads`)।
- কেউ সরাসরি ফাইলের লিংক পায় না। API শুধু যার দেখার অনুমতি আছে তাকে সাইন করা, মেয়াদি লিংক দেয় (ভিডিও ৪ ঘণ্টা, CV ১৫ মিনিট)। শেয়ার করা লিংক মেয়াদ শেষে কাজ করে না।
- ভিডিও HTTP Range দিয়ে চলে, তাই শিক্ষার্থী সামনে-পেছনে টানলে পুরো ফাইল নামাতে হয় না।
- কোর্সের ছবি পাবলিক, স্থায়ী লিংকে (`/api/v1/images/<id>`)।
- ব্যাকআপ: `docs/DEPLOY.md`-এর ব্যাকআপ অংশে `uploads` ভলিউমও রাখুন।

কত জায়গা লাগবে: ১ ঘণ্টার 720p ভিডিও মোটামুটি ৫০০ MB–১ GB। ৪০ GB ডিস্কের VPS-এ শুরুতে ৩০–৫০ ঘণ্টার কোর্স রাখা যায়। বেশি হলে নিচের যেকোনো ক্লাউডে যান।

## পরে Firebase Storage-এ নেওয়া

1. Firebase Console → Storage চালু করুন, বাকেটের নাম নিন (যেমন `techdropout.appspot.com`)।
2. `backend`-এ `npm i firebase-admin`।
3. `storage.ts`-এ `NotConfiguredDriver`-এর জায়গায় একটা `FirebaseDriver` লিখুন। প্রতিটা মেথড এক-দুই লাইনের:
   - `putFile(key, path)` → `bucket.upload(path, { destination: key })`
   - `putBuffer(key, data)` → `bucket.file(key).save(data)`
   - `size(key)` → `(await bucket.file(key).getMetadata())[0].size`
   - `read(key, range)` → `bucket.file(key).createReadStream(range)`
   - `remove(key)` → `bucket.file(key).delete({ ignoreNotFound: true })`
   - `directUrl(key, ttl)` → `bucket.file(key).getSignedUrl({ action: 'read', expires: Date.now() + ttl * 1000 })`
     (এটা দিলে ভিডিও সরাসরি Firebase থেকে চলে, আপনার সার্ভারের ব্যান্ডউইথ লাগে না)
4. `createDriver()`-এ `if (kind === 'firebase') return new FirebaseDriver(...)` যোগ করুন।
5. `.env`-এ `STORAGE_DRIVER=firebase` আর `FIREBASE_STORAGE_BUCKET=...` দিন, API রিস্টার্ট করুন।
6. পুরনো ফাইলগুলো `/data/uploads` থেকে একই নামে (যেমন `video/<id>`) বাকেটে কপি করুন (`gsutil -m cp -r /data/uploads/* gs://BUCKET/`)।

S3, Cloudflare R2 বা Bunny Storage-এর জন্যও একই পাঁচটা মেথড; শুধু SDK আলাদা।

`STORAGE_DRIVER`-এ এমন কিছু দিলে যেটা এখনো লেখা হয়নি, প্রোডাকশনে সার্ভার চালুই হবে না, যাতে আপলোড চুপচাপ হারিয়ে না যায়।

## লেসনে ভিডিওর তিন রকম উৎস

| লেসনে যা থাকে | কীভাবে চলে |
|---|---|
| আপলোড করা ফাইল | উপরের স্টোরেজ থেকে, সাইন করা লিংকে |
| `https://…` লিংক (YouTube, Vimeo, MP4) | লিংক যেমন আছে; YouTube/Vimeo বাইরের অ্যাপে খোলে |
| শুধু একটা কী (পুরনো Bunny CDN সেটআপ) | `MEDIA_BASE_URL` + `MEDIA_SIGNING_KEY` দিয়ে সাইন করা |

## সংশ্লিষ্ট `.env` সেটিংস

| নাম | মানে |
|---|---|
| `STORAGE_DRIVER` | `local` (ডিফল্ট) |
| `UPLOAD_DIR` | ফাইলের ফোল্ডার (Docker নিজে দেয়) |
| `UPLOAD_TMP_DIR` | বড় ভিডিও প্রথমে যেখানে নামে (Docker নিজে দেয়) |
| `MAX_VIDEO_MB` | প্রতি ভিডিওর সর্বোচ্চ আকার, ডিফল্ট ২০০০ |
| `FILE_SIGNING_KEY` | লিংক সাইন করার গোপন কী |
