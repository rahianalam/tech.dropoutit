/**
 * Demo content so the app looks alive before real teachers join:
 * instructors, ~14 courses with full curriculum, students, reviews, employers and jobs.
 *
 *   npm run seed:demo                       (local)
 *   docker compose exec api node dist/seed/demo.js   (server)
 *   ... --remove                            deletes everything this script created
 *
 * Every demo account uses an @demo.tech.dropout.it email and the password "demo12345",
 * so it is easy to find and remove later from the admin panel or with --remove.
 * Lesson videos point at public sample videos; replace them by uploading real ones.
 */
import { CourseLevel, JobType, PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();
const DOMAIN = '@demo.tech.dropout.it';
const SAMPLE = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/';
const VIDEOS = ['ForBiggerBlazes.mp4', 'ForBiggerEscapes.mp4', 'ForBiggerFun.mp4', 'ForBiggerJoyrides.mp4', 'ForBiggerMeltdowns.mp4'];

const teachers = [
  { key: 'tanvir', name: 'Tanvir Ahmed', headline: 'Senior Full-Stack Engineer · 10 yrs', skills: ['JavaScript', 'React', 'Node.js'],
    bio: 'Built products for startups in Dhaka and Berlin. I teach the way I wish someone had taught me: small steps, real projects.' },
  { key: 'nusrat', name: 'Nusrat Jahan', headline: 'Flutter GDE · Mobile Lead', skills: ['Flutter', 'Dart', 'Firebase'],
    bio: 'Shipped 20+ apps to Play Store and App Store. Loves clean architecture and beautiful UI.' },
  { key: 'arif', name: 'Arif Hossain', headline: 'Brand & UI Designer', skills: ['Figma', 'Illustrator', 'Branding'],
    bio: 'Designed for 300+ clients on Fiverr and Upwork. Top Rated Plus freelancer.' },
  { key: 'sadia', name: 'Sadia Rahman', headline: 'Growth Marketer · Ex-agency lead', skills: ['SEO', 'Facebook Ads', 'Content'],
    bio: 'Ran campaigns for e-commerce brands across Bangladesh. Data first, then creativity.' },
  { key: 'farhan', name: 'Farhan Kabir', headline: 'Data Scientist · Python & AI', skills: ['Python', 'Pandas', 'Machine Learning'],
    bio: 'Works on ML systems for fintech. Makes math feel friendly.' },
];

type C = {
  t: string; cat: string; title: string; subtitle: string; price: number; was?: number; level: CourseLevel; lang: 'bn' | 'en';
  featured?: boolean; outcomes: string[]; requirements: string[]; audience: string[]; sections: [string, string[]][];
};

const courses: C[] = [
  { t: 'tanvir', cat: 'web-development', title: 'Complete Web Development Bootcamp 2026', subtitle: 'HTML, CSS, JavaScript, React and Node.js — from zero to your first job',
    price: 2499, was: 5999, level: 'BEGINNER', lang: 'bn', featured: true,
    outcomes: ['Build responsive websites with HTML5 and modern CSS', 'Write real JavaScript: DOM, fetch, async/await', 'Create single-page apps with React', 'Build a REST API with Node.js and Express', 'Deploy your projects online for free', 'Prepare a portfolio that gets interviews'],
    requirements: ['A computer with internet', 'No programming experience needed'],
    audience: ['Complete beginners who want a tech career', 'Students and freelancers who want to build websites'],
    sections: [['Getting started', ['Welcome and how to learn', 'Setting up VS Code', 'How the web works']],
      ['HTML & CSS', ['Your first HTML page', 'CSS selectors and the box model', 'Flexbox in practice', 'Responsive design with Grid']],
      ['JavaScript', ['Variables and types', 'Functions and arrays', 'DOM and events', 'Fetching data from an API']],
      ['React', ['Components and props', 'State and hooks', 'Building a todo app']],
      ['Backend & deploy', ['Node.js and Express', 'Connecting a database', 'Deploying your app']]] },
  { t: 'tanvir', cat: 'web-development', title: 'JavaScript for Absolute Beginners', subtitle: 'Understand JavaScript deeply with 50+ small exercises',
    price: 0, level: 'BEGINNER', lang: 'bn',
    outcomes: ['Think like a programmer', 'Use variables, loops and functions', 'Work with arrays and objects', 'Solve beginner coding problems'],
    requirements: ['Basic computer skills'], audience: ['Anyone starting programming'],
    sections: [['Basics', ['What is JavaScript?', 'Variables', 'Conditions']], ['Practice', ['Loops', 'Functions', 'Mini project: calculator']]] },
  { t: 'tanvir', cat: 'web-development', title: 'Next.js & TypeScript: Production Apps', subtitle: 'Server components, auth, payments and deployment',
    price: 1999, was: 3999, level: 'ADVANCED', lang: 'en',
    outcomes: ['Use the App Router and server components', 'Type everything with TypeScript', 'Add auth and payments', 'Deploy with CI'],
    requirements: ['Comfortable with React'], audience: ['React developers ready for production work'],
    sections: [['Foundations', ['Why Next.js', 'Routing and layouts', 'Data fetching']], ['Real features', ['Authentication', 'Payments', 'Deploying']]] },
  { t: 'nusrat', cat: 'app-development', title: 'Flutter & Dart: Build Real Android and iOS Apps', subtitle: 'Design, state management, Firebase and publishing to Play Store',
    price: 2999, was: 6499, level: 'ALL', lang: 'bn', featured: true,
    outcomes: ['Build beautiful UIs with Flutter widgets', 'Manage state with Riverpod', 'Use Firebase auth and Firestore', 'Publish to Google Play Store', 'Structure apps that are easy to grow'],
    requirements: ['Basic programming knowledge helps', 'A laptop with 8 GB RAM'],
    audience: ['Beginners who want to build apps', 'Web developers moving to mobile'],
    sections: [['Introduction', ['Why Flutter', 'Installing Flutter', 'Your first app']],
      ['Dart language', ['Variables and functions', 'Classes and null safety', 'Async programming']],
      ['Building UI', ['Layouts: Row, Column, Stack', 'Lists and grids', 'Navigation', 'Themes and dark mode']],
      ['Real app', ['State with Riverpod', 'Firebase login', 'Saving data', 'Publishing to Play Store']]] },
  { t: 'nusrat', cat: 'app-development', title: 'Firebase for Mobile Developers', subtitle: 'Auth, Firestore, Storage and push notifications',
    price: 999, was: 1999, level: 'INTERMEDIATE', lang: 'en',
    outcomes: ['Sign users in with email and Google', 'Model data in Firestore', 'Upload files to Storage', 'Send push notifications'],
    requirements: ['Know the basics of Flutter or Android'], audience: ['Mobile developers'],
    sections: [['Setup', ['Creating a project', 'Connecting your app']], ['Features', ['Authentication', 'Firestore', 'Cloud Storage', 'Push notifications']]] },
  { t: 'arif', cat: 'graphics-design', title: 'Graphic Design Masterclass: Zero to Freelancer', subtitle: 'Logo, branding and social media design with Illustrator and Photoshop',
    price: 1499, was: 3499, level: 'BEGINNER', lang: 'bn', featured: true,
    outcomes: ['Master Illustrator and Photoshop basics', 'Design logos clients love', 'Create brand identity kits', 'Design social media posts that convert', 'Win your first client online'],
    requirements: ['A computer that runs Adobe apps'], audience: ['Beginners who want to earn with design'],
    sections: [['Design basics', ['Colour theory', 'Typography', 'Layout and grids']], ['Illustrator', ['Pen tool', 'Logo design', 'Brand kit']], ['Photoshop', ['Photo editing', 'Social media posts']], ['Freelancing', ['Building a portfolio', 'Getting the first order']]] },
  { t: 'arif', cat: 'graphics-design', title: 'UI/UX Design with Figma', subtitle: 'Design modern apps and websites, from wireframe to prototype',
    price: 1299, was: 2999, level: 'ALL', lang: 'bn',
    outcomes: ['Use Figma like a pro', 'Design with auto-layout and components', 'Run simple user research', 'Make clickable prototypes'],
    requirements: ['No design experience needed'], audience: ['Aspiring UI/UX designers', 'Developers who want better design skills'],
    sections: [['Figma basics', ['Frames and layers', 'Auto layout', 'Components']], ['UX process', ['User research', 'Wireframes', 'Prototype and test']]] },
  { t: 'arif', cat: 'graphics-design', title: 'Canva Design in 2 Hours', subtitle: 'Make professional posts, CVs and presentations fast',
    price: 0, level: 'BEGINNER', lang: 'bn',
    outcomes: ['Design social posts', 'Make a modern CV', 'Create presentations'], requirements: ['None'], audience: ['Students, shop owners, anyone'],
    sections: [['Canva quick start', ['Tour of Canva', 'Social media post', 'CV design', 'Presentation']]] },
  { t: 'sadia', cat: 'digital-marketing', title: 'Digital Marketing A to Z', subtitle: 'SEO, Facebook ads, content and email — with real campaigns',
    price: 1799, was: 3999, level: 'ALL', lang: 'bn', featured: true,
    outcomes: ['Plan a marketing strategy', 'Rank on Google with SEO', 'Run profitable Facebook and Instagram ads', 'Write content that sells', 'Measure results with analytics'],
    requirements: ['No experience needed'], audience: ['Business owners', 'Students who want a marketing career'],
    sections: [['Strategy', ['Marketing funnel', 'Know your customer']], ['SEO', ['Keyword research', 'On-page SEO', 'Link building']], ['Social ads', ['Facebook Ads Manager', 'Targeting', 'Optimising campaigns']], ['Analytics', ['Google Analytics', 'Reporting']]] },
  { t: 'sadia', cat: 'digital-marketing', title: 'Facebook Ads for Small Business', subtitle: 'Sell more with a small budget',
    price: 799, was: 1499, level: 'BEGINNER', lang: 'bn',
    outcomes: ['Set up Business Manager', 'Create ads that convert', 'Retarget visitors'], requirements: ['A Facebook page'], audience: ['F-commerce sellers'],
    sections: [['Ads basics', ['Business Manager setup', 'Your first campaign', 'Retargeting']]] },
  { t: 'farhan', cat: 'data-ai', title: 'Python for Data Science & AI', subtitle: 'Python, Pandas, visualisation and your first machine learning models',
    price: 2199, was: 4999, level: 'BEGINNER', lang: 'en', featured: true,
    outcomes: ['Write clean Python', 'Analyse data with Pandas', 'Make charts with Matplotlib', 'Train ML models with scikit-learn', 'Understand how ChatGPT-style AI works'],
    requirements: ['High-school math'], audience: ['Students curious about AI', 'Analysts who use Excel today'],
    sections: [['Python basics', ['Installing Python', 'Data types', 'Functions']], ['Data analysis', ['NumPy', 'Pandas', 'Visualisation']], ['Machine learning', ['Regression', 'Classification', 'Your first AI project']]] },
  { t: 'farhan', cat: 'data-ai', title: 'ChatGPT & AI Tools for Productivity', subtitle: 'Work 10x faster with AI — writing, research and automation',
    price: 0, level: 'ALL', lang: 'bn',
    outcomes: ['Write great prompts', 'Use AI for study and work', 'Automate boring tasks'], requirements: ['None'], audience: ['Everyone'],
    sections: [['AI tools', ['What AI can and cannot do', 'Prompting basics', 'AI for writing', 'AI for research']]] },
  { t: 'sadia', cat: 'freelancing', title: 'Freelancing Success on Upwork & Fiverr', subtitle: 'Profile, proposals and pricing that win clients',
    price: 999, was: 2499, level: 'BEGINNER', lang: 'bn',
    outcomes: ['Create a profile that stands out', 'Write proposals that get replies', 'Price your work', 'Get paid safely to Bangladesh'],
    requirements: ['One skill you can offer'], audience: ['New freelancers'],
    sections: [['Getting started', ['Choosing a marketplace', 'Profile that converts']], ['Winning work', ['Proposals', 'Pricing', 'Getting paid via Payoneer']]] },
  { t: 'farhan', cat: 'spoken-english', title: 'Spoken English for Interviews', subtitle: 'Speak with confidence in job interviews and client calls',
    price: 499, was: 999, level: 'BEGINNER', lang: 'bn',
    outcomes: ['Introduce yourself fluently', 'Answer common interview questions', 'Talk to foreign clients'], requirements: ['Basic English reading'], audience: ['Job seekers', 'Freelancers'],
    sections: [['Speaking', ['Introducing yourself', 'Common questions', 'Client calls']]] },
  { t: 'tanvir', cat: 'office-productivity', title: 'Excel from Beginner to Advanced', subtitle: 'Formulas, pivot tables and dashboards for office jobs',
    price: 699, was: 1499, level: 'ALL', lang: 'bn',
    outcomes: ['Use the 50 most useful formulas', 'Build pivot tables', 'Make dashboards'], requirements: ['Excel installed'], audience: ['Office workers', 'Students'],
    sections: [['Excel', ['Basics', 'Formulas', 'Pivot tables', 'Dashboards']]] },
];

const students = ['Rakib Hasan', 'Mim Akter', 'Shuvo Das', 'Nadia Islam', 'Imran Khan', 'Tania Sultana', 'Sabbir Hossain', 'Lamia Chowdhury',
  'Fahim Rahman', 'Jannat Ara', 'Mehedi Hasan', 'Sumaiya Khan', 'Rafi Ahmed', 'Anika Tabassum', 'Tamim Iqbal', 'Riya Sen'];
const comments = [
  'Best course I have taken. Everything is explained step by step.',
  'Very practical. I built my first project in the second week!',
  'The instructor explains complex topics in a simple way. Highly recommended.',
  'Great content and great examples. Would love more exercises.',
  'Got my first freelance order after finishing this course.',
  'Clear audio, clear explanations. Worth every taka.',
  'Good course, a little fast in some parts but rewinding helps.',
  'Exactly what I needed for my job interview preparation.',
];

const employers = [
  { key: 'pixel', name: 'Pixel Forge HR', company: 'Pixel Forge Ltd', location: 'Dhaka', about: 'A product studio building apps for clients in 12 countries.' },
  { key: 'shop', name: 'ShopBD Careers', company: 'ShopBD', location: 'Chattogram', about: 'Fast-growing e-commerce brand.' },
];
const jobs: { e: string; title: string; type: JobType; skills: string[]; min: number; max: number; location: string; desc: string }[] = [
  { e: 'pixel', title: 'Junior Flutter Developer', type: 'FULL_TIME', skills: ['Flutter', 'Dart', 'Firebase'], min: 35000, max: 55000, location: 'Dhaka (Hybrid)',
    desc: 'Build and ship features for client apps. You will work with senior engineers who review your code and help you grow.' },
  { e: 'pixel', title: 'React Frontend Intern', type: 'INTERNSHIP', skills: ['JavaScript', 'React', 'CSS'], min: 12000, max: 18000, location: 'Remote',
    desc: 'A 6-month paid internship. Turn Figma designs into fast React pages. Great first job for bootcamp graduates.' },
  { e: 'shop', title: 'Digital Marketing Executive', type: 'FULL_TIME', skills: ['Facebook Ads', 'SEO', 'Content'], min: 25000, max: 40000, location: 'Chattogram',
    desc: 'Plan and run ad campaigns, manage our social pages and report on results every week.' },
  { e: 'shop', title: 'Graphic Designer (Part-time)', type: 'PART_TIME', skills: ['Illustrator', 'Photoshop', 'Canva'], min: 15000, max: 22000, location: 'Remote',
    desc: 'Design social posts, banners and product photos for campaigns.' },
];

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '.');

async function remove() {
  const users = await prisma.user.findMany({ where: { email: { endsWith: DOMAIN } }, select: { id: true } });
  const ids = users.map((u) => u.id);
  const courseIds = (await prisma.course.findMany({ where: { teacherId: { in: ids } }, select: { id: true } })).map((c) => c.id);
  await prisma.$transaction([
    prisma.review.deleteMany({ where: { OR: [{ userId: { in: ids } }, { courseId: { in: courseIds } }] } }),
    prisma.lessonProgress.deleteMany({ where: { enrollment: { OR: [{ userId: { in: ids } }, { courseId: { in: courseIds } }] } } }),
    prisma.enrollment.deleteMany({ where: { OR: [{ userId: { in: ids } }, { courseId: { in: courseIds } }] } }),
    prisma.course.deleteMany({ where: { id: { in: courseIds } } }),
    prisma.jobApplication.deleteMany({ where: { OR: [{ seekerId: { in: ids } }, { job: { employerId: { in: ids } } }] } }),
    prisma.job.deleteMany({ where: { employerId: { in: ids } } }),
    prisma.notification.deleteMany({ where: { userId: { in: ids } } }),
    prisma.refreshToken.deleteMany({ where: { userId: { in: ids } } }),
    prisma.userRole.deleteMany({ where: { userId: { in: ids } } }),
    prisma.user.deleteMany({ where: { id: { in: ids } } }),
  ]);
  console.log(`Removed ${ids.length} demo accounts and ${courseIds.length} demo courses.`);
}

async function main() {
  if (process.argv.includes('--remove')) return remove();
  if (await prisma.user.findFirst({ where: { email: `tanvir${DOMAIN}` } })) {
    console.log('Demo content already exists (run with --remove first to recreate it).');
    return;
  }
  const passwordHash = await bcrypt.hash('demo12345', 10);
  const cats = new Map((await prisma.category.findMany()).map((c) => [c.slug, c.id]));

  const teacherIds = new Map<string, string>();
  for (const t of teachers) {
    const u = await prisma.user.create({
      data: {
        name: t.name, email: `${t.key}${DOMAIN}`, passwordHash,
        roles: { create: [{ role: 'TEACHER' }, { role: 'STUDENT' }] },
        teacherProfile: { create: { headline: t.headline, bio: t.bio, skills: t.skills } },
      },
    });
    teacherIds.set(t.key, u.id);
  }

  const studentIds: string[] = [];
  for (const name of students) {
    const u = await prisma.user.create({
      data: { name, email: `${slug(name)}${DOMAIN}`, passwordHash, roles: { create: [{ role: 'STUDENT' }, { role: 'JOB_SEEKER' }] } },
    });
    studentIds.push(u.id);
  }

  let v = 0;
  for (const [ci, c] of courses.entries()) {
    const course = await prisma.course.create({
      data: {
        teacherId: teacherIds.get(c.t)!, categoryId: cats.get(c.cat) ?? null,
        title: c.title, subtitle: c.subtitle,
        description: `${c.subtitle}.\n\nThis course is fully project based. Every section ends with a small task, so you practise what you learn right away. You get lifetime access, can learn at your own pace on your phone, and can ask the instructor questions anytime.\n\nBy the end you will have real work to show in your portfolio.`,
        pricePaisa: c.price * 100, originalPricePaisa: c.was ? c.was * 100 : null, isFree: c.price === 0,
        level: c.level, language: c.lang, status: 'PUBLISHED', isFeatured: !!c.featured,
        outcomes: c.outcomes, requirements: c.requirements, audience: c.audience,
        publishedAt: new Date(Date.now() - (courses.length - ci) * 5 * 864e5),
        sections: {
          create: c.sections.map(([title, lessons], si) => ({
            title, position: si,
            lessons: {
              create: lessons.map((lt, li) => ({
                title: lt, position: li, type: 'VIDEO' as const,
                mediaKey: SAMPLE + VIDEOS[v++ % VIDEOS.length],
                durationSec: 180 + ((ci * 7 + si * 5 + li * 11) % 15) * 60,
                isPreview: si === 0 && li < 2,
              })),
            },
          })),
        },
      },
    });

    // Some students enrol and review (more for featured courses).
    const n = c.featured ? 12 : 4 + (ci % 6);
    for (let k = 0; k < n; k++) {
      const userId = studentIds[(ci * 3 + k) % studentIds.length];
      await prisma.enrollment.create({ data: { userId, courseId: course.id, progressPct: (k * 17) % 100 } });
      if (k < n - 2) {
        await prisma.review.create({
          data: { userId, courseId: course.id, rating: k % 5 === 4 ? 4 : 5 - (k % 7 === 6 ? 1 : 0), comment: comments[(ci + k) % comments.length] },
        });
      }
    }
    const agg = await prisma.review.aggregate({ where: { courseId: course.id }, _avg: { rating: true }, _count: true });
    await prisma.course.update({ where: { id: course.id }, data: { ratingAvg: agg._avg.rating ?? 0, ratingCount: agg._count } });
  }

  const employerIds = new Map<string, string>();
  for (const e of employers) {
    const u = await prisma.user.create({
      data: {
        name: e.name, email: `${e.key}${DOMAIN}`, passwordHash,
        roles: { create: [{ role: 'EMPLOYER' }] },
        employerProfile: { create: { companyName: e.company, location: e.location, about: e.about, verified: true } },
      },
    });
    employerIds.set(e.key, u.id);
  }
  for (const j of jobs) {
    await prisma.job.create({
      data: {
        employerId: employerIds.get(j.e)!, title: j.title, description: j.desc, skills: j.skills, type: j.type, location: j.location,
        salaryMin: j.min, salaryMax: j.max, status: 'LIVE', publishedAt: new Date(), deadline: new Date(Date.now() + 30 * 864e5),
      },
    });
  }
  console.log(`Demo ready: ${teachers.length} teachers, ${courses.length} courses, ${students.length} students, ${jobs.length} jobs. Password: demo12345`);
}

main()
  .catch((e) => { console.error(e); process.exitCode = 1; })
  .finally(() => prisma.$disconnect());
