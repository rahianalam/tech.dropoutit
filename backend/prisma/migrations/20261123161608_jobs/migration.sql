-- CreateEnum
CREATE TYPE "UploadKind" AS ENUM ('CV', 'LOGO');

-- AlterTable
ALTER TABLE "EmployerProfile" ADD COLUMN     "about" TEXT,
ADD COLUMN     "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "location" TEXT;

-- AlterTable
ALTER TABLE "Job" ADD COLUMN     "publishedAt" TIMESTAMP(3),
ADD COLUMN     "rejectReason" TEXT,
ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "JobApplication" DROP COLUMN "cvUrl",
ADD COLUMN     "cvLink" TEXT,
ADD COLUMN     "cvUploadId" TEXT,
ADD COLUMN     "note" TEXT,
ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- CreateTable
CREATE TABLE "SeekerProfile" (
    "userId" TEXT NOT NULL,
    "headline" TEXT NOT NULL,
    "about" TEXT,
    "skills" TEXT[],
    "location" TEXT,
    "cvUploadId" TEXT,
    "cvLink" TEXT,
    "openToWork" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SeekerProfile_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "Upload" (
    "id" TEXT NOT NULL,
    "ownerId" TEXT NOT NULL,
    "kind" "UploadKind" NOT NULL,
    "mime" TEXT NOT NULL,
    "size" INTEGER NOT NULL,
    "originalName" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Upload_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Job_status_publishedAt_idx" ON "Job"("status", "publishedAt");

-- CreateIndex
CREATE INDEX "JobApplication_seekerId_idx" ON "JobApplication"("seekerId");

-- AddForeignKey
ALTER TABLE "SeekerProfile" ADD CONSTRAINT "SeekerProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SeekerProfile" ADD CONSTRAINT "SeekerProfile_cvUploadId_fkey" FOREIGN KEY ("cvUploadId") REFERENCES "Upload"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Upload" ADD CONSTRAINT "Upload_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "JobApplication" ADD CONSTRAINT "JobApplication_cvUploadId_fkey" FOREIGN KEY ("cvUploadId") REFERENCES "Upload"("id") ON DELETE SET NULL ON UPDATE CASCADE;

