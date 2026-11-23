-- DropIndex
DROP INDEX "Booking_teacherId_startAt_key";

-- AlterTable
ALTER TABLE "Booking" ADD COLUMN     "cancelledBy" TEXT,
ADD COLUMN     "pricePaisa" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "reminded15" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "reminded24" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "slotLock" TEXT DEFAULT 'live';

-- CreateIndex
CREATE INDEX "Booking_studentId_idx" ON "Booking"("studentId");

-- CreateIndex
CREATE UNIQUE INDEX "Booking_teacherId_startAt_slotLock_key" ON "Booking"("teacherId", "startAt", "slotLock");

