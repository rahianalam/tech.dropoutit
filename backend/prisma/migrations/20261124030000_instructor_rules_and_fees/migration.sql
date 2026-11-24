-- CreateEnum
CREATE TYPE "StoragePlan" AS ENUM ('FREE', 'STARTER', 'PRO', 'UNLIMITED');

-- AlterEnum
ALTER TYPE "BookingStatus" ADD VALUE 'REQUESTED';

-- AlterEnum
ALTER TYPE "OrderItemType" ADD VALUE 'STORAGE_PLAN';

-- AlterTable
ALTER TABLE "Booking" ADD COLUMN     "declineNote" TEXT,
ADD COLUMN     "respondBy" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Course" ADD COLUMN     "views" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "LedgerEntry" ADD COLUMN     "commissionPaisa" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "grossPaisa" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "vatPaisa" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "PlatformSettings" ADD COLUMN     "bookingResponseHours" INTEGER NOT NULL DEFAULT 24,
ADD COLUMN     "freeCoursesRequired" INTEGER NOT NULL DEFAULT 10,
ADD COLUMN     "freeVideoLimit" INTEGER NOT NULL DEFAULT 10,
ADD COLUMN     "goldCourseCommissionBps" INTEGER NOT NULL DEFAULT 500,
ADD COLUMN     "goldSales" INTEGER NOT NULL DEFAULT 50,
ADD COLUMN     "proPricePaisa" INTEGER NOT NULL DEFAULT 49900,
ADD COLUMN     "proVideoLimit" INTEGER NOT NULL DEFAULT 200,
ADD COLUMN     "silverCourseCommissionBps" INTEGER NOT NULL DEFAULT 600,
ADD COLUMN     "silverSales" INTEGER NOT NULL DEFAULT 25,
ADD COLUMN     "starterPricePaisa" INTEGER NOT NULL DEFAULT 19900,
ADD COLUMN     "starterVideoLimit" INTEGER NOT NULL DEFAULT 50,
ADD COLUMN     "unlimitedPricePaisa" INTEGER NOT NULL DEFAULT 99900,
ADD COLUMN     "vatBps" INTEGER NOT NULL DEFAULT 500,
ADD COLUMN     "viewsRequired" INTEGER NOT NULL DEFAULT 4000,
ADD COLUMN     "watchMinutesRequired" INTEGER NOT NULL DEFAULT 10000,
ALTER COLUMN "courseCommissionBps" SET DEFAULT 700,
ALTER COLUMN "sessionCommissionBps" SET DEFAULT 1000;

-- AlterTable
ALTER TABLE "TeacherProfile" ADD COLUMN     "canSellPaid" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "experience" TEXT,
ADD COLUMN     "expertise" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "hourlyRatePaisa" INTEGER,
ADD COLUMN     "rulesAcceptedAt" TIMESTAMP(3),
ADD COLUMN     "storagePlan" "StoragePlan" NOT NULL DEFAULT 'FREE',
ADD COLUMN     "storagePlanUntil" TIMESTAMP(3),
ADD COLUMN     "verifiedAt" TIMESTAMP(3);


-- The person's new fee rules replace the old defaults (30% / 20%).
UPDATE "PlatformSettings" SET "courseCommissionBps" = 700, "sessionCommissionBps" = 1000;
-- Instructors who already exist keep selling paid courses; the free-first rule is for new instructors.
UPDATE "TeacherProfile" SET "canSellPaid" = true;
-- Existing hourly price from the 1-hour slots they already set.
UPDATE "TeacherProfile" tp SET "hourlyRatePaisa" = r.rate FROM (
  SELECT "teacherId", MAX("pricePaisa" * 60 / "slotMinutes") AS rate FROM "AvailabilityRule" WHERE "pricePaisa" > 0 GROUP BY "teacherId"
) r WHERE r."teacherId" = tp."userId";
