import { Controller, Get, Header, Module } from '@nestjs/common';
import { Public } from '../common/auth.decorators';

const CONTACT = process.env.SUPPORT_EMAIL ?? 'support@tech.dropout.it';
const UPDATED = '23 November 2026';

const page = (title: string, body: string) => `<!doctype html>
<html lang="bn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · Tech.Dropout</title>
<style>
  body{font-family:system-ui,-apple-system,"Noto Sans Bengali",sans-serif;max-width:760px;margin:0 auto;padding:24px 16px 64px;line-height:1.7;color:#1c1b1f;background:#fdfbff}
  h1{color:#5b3df5;font-size:1.6rem} h2{font-size:1.15rem;margin-top:2rem} li{margin:.3rem 0}
  .en{color:#555;border-top:1px solid #ddd;margin-top:3rem;padding-top:1rem} small{color:#777}
  @media (prefers-color-scheme:dark){body{background:#141218;color:#e6e0e9}.en{color:#bbb;border-color:#333}}
</style></head><body>${body}</body></html>`;

/** Public pages the stores ask for: a privacy policy and a way to delete an account. */
@Controller()
export class LegalController {
  @Public() @Get('privacy') @Header('Content-Type', 'text/html; charset=utf-8')
  privacy() {
    return page('প্রাইভেসি পলিসি', `
<h1>প্রাইভেসি পলিসি</h1><small>সর্বশেষ আপডেট: ${UPDATED}</small>
<p>Tech.Dropout (tech.dropout.it) একটি স্কিল শেখার ও কাজ খোঁজার প্ল্যাটফর্ম। আমরা কী তথ্য রাখি এবং কেন, তা এখানে লেখা আছে।</p>
<h2>যে তথ্য আমরা রাখি</h2>
<ul>
<li><b>অ্যাকাউন্ট:</b> নাম, ইমেইল বা মোবাইল নম্বর, পাসওয়ার্ড (এনক্রিপ্ট করা অবস্থায়)।</li>
<li><b>শেখা:</b> কোন কোর্সে এনরোল করেছেন, কতটা শেষ করেছেন, রিভিউ ও রেটিং।</li>
<li><b>টিচার আবেদন ও প্রোফাইল:</b> পরিচিতি, স্কিল, পোর্টফোলিও লিংক, পেমেন্ট নেওয়ার অ্যাকাউন্ট (bKash/Nagad/ব্যাংক)।</li>
<li><b>জবস:</b> জব প্রোফাইল, স্কিল, CV ফাইল বা লিংক, আবেদন; কোম্পানির তথ্য ও জব পোস্ট।</li>
<li><b>পেমেন্ট:</b> অর্ডার, টাকার পরিমাণ, লেনদেন নম্বর। কার্ড বা মোবাইল ব্যাংকিংয়ের পিন/পাসওয়ার্ড আমরা কখনো দেখি না, সেটা SSLCommerz-এর পেজে দেওয়া হয়।</li>
<li><b>ফোন:</b> পুশ নোটিফিকেশনের জন্য একটি ডিভাইস টোকেন।</li>
</ul>
<h2>কেন ব্যবহার করি</h2>
<ul><li>অ্যাকাউন্ট চালাতে, কোর্স ও সেশন দিতে, পেমেন্ট নিতে ও টিচারকে টাকা পাঠাতে।</li>
<li>আপনি যে কোম্পানিতে আবেদন করেন, শুধু তারাই আপনার জব প্রোফাইল ও CV দেখে।</li>
<li>বুকিং, আবেদন ও পেমেন্টের খবর নোটিফিকেশনে জানাতে।</li></ul>
<p>আমরা আপনার তথ্য বিক্রি করি না এবং বিজ্ঞাপনের জন্য ব্যবহার করি না।</p>
<h2>কাদের সাথে শেয়ার হয়</h2>
<ul><li>SSLCommerz (পেমেন্ট), Google Firebase (পুশ নোটিফিকেশন), ভিডিও হোস্টিং ও Jitsi (লাইভ সেশন)। শুধু সেবা দিতে যতটুকু দরকার।</li>
<li>আইন অনুযায়ী বাধ্য হলে সরকারি কর্তৃপক্ষ।</li></ul>
<h2>নিরাপত্তা</h2>
<p>সব যোগাযোগ HTTPS দিয়ে হয়। পাসওয়ার্ড হ্যাশ করে রাখা হয়। CV ফাইল পাবলিক নয়, মেয়াদি লিংক দিয়েই শুধু খোলা যায়।</p>
<h2>আপনার অধিকার ও অ্যাকাউন্ট ডিলিট</h2>
<p>অ্যাপের প্রোফাইল থেকে নিজের তথ্য বদলাতে পারেন এবং যেকোনো সময় অ্যাকাউন্ট ডিলিট করতে পারেন। বিস্তারিত: <a href="/delete-account">অ্যাকাউন্ট ডিলিট</a>।</p>
<h2>শিশু</h2><p>১৩ বছরের কম বয়সীদের জন্য এই সেবা নয়।</p>
<h2>যোগাযোগ</h2><p>${CONTACT}</p>
<div class="en"><h2>English summary</h2>
<p>We store your account details, learning progress, teacher/job profiles, CVs, orders and a push token to run the service. Payments are handled by SSLCommerz; we never see card or mobile-banking PINs. CVs are visible only to companies you apply to. We do not sell your data or use it for ads. Service providers: SSLCommerz, Google Firebase, video hosting, Jitsi. You can edit your data and delete your account in the app at any time (<a href="/delete-account">how</a>). Contact: ${CONTACT}.</p></div>`);
  }

  @Public() @Get('delete-account') @Header('Content-Type', 'text/html; charset=utf-8')
  deleteAccount() {
    return page('অ্যাকাউন্ট ডিলিট', `
<h1>Tech.Dropout অ্যাকাউন্ট ডিলিট করবেন যেভাবে</h1>
<ol><li>অ্যাপ খুলে <b>প্রোফাইল</b> ট্যাবে যান।</li>
<li><b>অ্যাকাউন্ট ডিলিট করুন</b> চাপুন।</li>
<li>পাসওয়ার্ড দিয়ে নিশ্চিত করুন।</li></ol>
<p>অ্যাপ না থাকলে আপনার অ্যাকাউন্টের ইমেইল/মোবাইল নম্বর থেকে <b>${CONTACT}</b>-এ লিখুন, ৭ দিনের মধ্যে ডিলিট করে দেব।</p>
<h2>যা মুছে যায়</h2>
<ul><li>নাম, ইমেইল, মোবাইল নম্বর, পাসওয়ার্ড</li><li>জব প্রোফাইল, CV ফাইল, পোর্টফোলিও, টিচার আবেদন, পেমেন্ট অ্যাকাউন্ট</li><li>নোটিফিকেশন ও ফোনের পুশ টোকেন</li></ul>
<h2>যা থেকে যায়</h2>
<p>অর্ডার ও পেমেন্টের হিসাব আইন ও রিফান্ডের জন্য রাখা হয়, কিন্তু আপনার নাম ছাড়া ("মুছে ফেলা অ্যাকাউন্ট" হিসেবে)। আগে দেওয়া রিভিউ নাম ছাড়া থাকতে পারে।</p>
<p>টিচারের অপরিশোধিত আয় থাকলে বা সামনে কোনো সেশন থাকলে আগে সেগুলো শেষ করতে হবে।</p>
<div class="en"><h2>English</h2><p>Open the app → Profile → Delete account → confirm with your password. Without the app, email ${CONTACT} from your account's email or phone and we delete it within 7 days. Deleted: name, email, phone, password, job profile, CV files, portfolio, teacher application, payout account, notifications, push tokens. Kept without your name: orders and payment records (required for accounting and refunds).</p></div>`);
  }
}

@Module({ controllers: [LegalController] })
export class LegalModule {}
