-- CreateEnum
CREATE TYPE "AffiliateStatus" AS ENUM ('UNPAID', 'IN_REVIEW', 'ACTIVE', 'REJECTED', 'DEACTIVATED');

-- AlterEnum
ALTER TYPE "OrderItemType" ADD VALUE 'AFFILIATE_MEMBERSHIP';

-- AlterEnum
ALTER TYPE "Role" ADD VALUE 'AFFILIATE';

-- AlterEnum
ALTER TYPE "UploadKind" ADD VALUE 'KYC';

-- AlterTable
ALTER TABLE "Enrollment" ADD COLUMN     "expiresAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "affiliateId" TEXT;

-- AlterTable
ALTER TABLE "PlatformSettings" ADD COLUMN     "affiliateCommissionBps" INTEGER NOT NULL DEFAULT 200,
ADD COLUMN     "affiliateFeePaisa" INTEGER NOT NULL DEFAULT 60000,
ADD COLUMN     "affiliateInactiveDays" INTEGER NOT NULL DEFAULT 180,
ADD COLUMN     "referralPassDays" INTEGER NOT NULL DEFAULT 15,
ADD COLUMN     "referralTarget" INTEGER NOT NULL DEFAULT 15;

-- AlterTable
ALTER TABLE "TeacherApplication" ADD COLUMN     "rulesAcceptedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "freePassUntil" TIMESTAMP(3),
ADD COLUMN     "referralCode" TEXT,
ADD COLUMN     "referralRewards" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "referredById" TEXT;

-- CreateTable
CREATE TABLE "AffiliateProfile" (
    "userId" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "status" "AffiliateStatus" NOT NULL DEFAULT 'UNPAID',
    "nidNumber" TEXT,
    "nidFrontId" TEXT,
    "nidBackId" TEXT,
    "photoId" TEXT,
    "selfieId" TEXT,
    "adminNote" TEXT,
    "membershipPaidAt" TIMESTAMP(3),
    "lastActiveAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "payoutMethod" TEXT,
    "payoutAccount" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AffiliateProfile_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "AffiliateClick" (
    "id" TEXT NOT NULL,
    "affiliateId" TEXT NOT NULL,
    "courseId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AffiliateClick_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AffiliateEarning" (
    "id" TEXT NOT NULL,
    "affiliateId" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "courseId" TEXT NOT NULL,
    "amountPaisa" INTEGER NOT NULL,
    "status" "LedgerStatus" NOT NULL DEFAULT 'PENDING',
    "availableAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AffiliateEarning_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "AffiliateProfile_code_key" ON "AffiliateProfile"("code");

-- CreateIndex
CREATE INDEX "AffiliateClick_affiliateId_createdAt_idx" ON "AffiliateClick"("affiliateId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "AffiliateEarning_orderId_key" ON "AffiliateEarning"("orderId");

-- CreateIndex
CREATE INDEX "AffiliateEarning_affiliateId_status_idx" ON "AffiliateEarning"("affiliateId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "User_referralCode_key" ON "User"("referralCode");

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_referredById_fkey" FOREIGN KEY ("referredById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AffiliateProfile" ADD CONSTRAINT "AffiliateProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AffiliateClick" ADD CONSTRAINT "AffiliateClick_affiliateId_fkey" FOREIGN KEY ("affiliateId") REFERENCES "AffiliateProfile"("userId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AffiliateEarning" ADD CONSTRAINT "AffiliateEarning_affiliateId_fkey" FOREIGN KEY ("affiliateId") REFERENCES "AffiliateProfile"("userId") ON DELETE CASCADE ON UPDATE CASCADE;

