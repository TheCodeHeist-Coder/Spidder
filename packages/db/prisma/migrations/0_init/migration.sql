-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "Difficulty" AS ENUM ('EASY', 'MEDIUM', 'HARD');

-- CreateEnum
CREATE TYPE "ProblemStatus" AS ENUM ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "Mode" AS ENUM ('ONE_V_ONE', 'TWO_V_TWO', 'THREE_V_THREE', 'FOUR_V_FOUR');

-- CreateEnum
CREATE TYPE "Side" AS ENUM ('A', 'B');

-- CreateEnum
CREATE TYPE "BattleStatus" AS ENUM ('LOBBY', 'COUNTDOWN', 'IN_PROGRESS', 'FINISHED', 'ABANDONED');

-- CreateEnum
CREATE TYPE "FinishReason" AS ENUM ('ALL_PASSED', 'TIMEOUT', 'FORFEIT');

-- CreateEnum
CREATE TYPE "TestKind" AS ENUM ('SAMPLE', 'HIDDEN');

-- CreateEnum
CREATE TYPE "SubmissionStatus" AS ENUM ('QUEUED', 'RUNNING', 'COMPLETED', 'ERROR');

-- CreateEnum
CREATE TYPE "Role" AS ENUM ('PLAYER', 'SUPER_ADMIN');

-- CreateEnum
CREATE TYPE "LeagueVisibility" AS ENUM ('PUBLIC', 'PRIVATE');

-- CreateEnum
CREATE TYPE "LeagueStatus" AS ENUM ('DRAFT', 'OPEN', 'RUNNING', 'FINISHED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "QualificationMode" AS ENUM ('TOP_N', 'WIN_COUNT');

-- CreateEnum
CREATE TYPE "LeagueRound" AS ENUM ('GROUP', 'TIEBREAK', 'QUARTER_FINAL', 'SEMI_FINAL', 'FINAL');

-- CreateEnum
CREATE TYPE "FixtureStatus" AS ENUM ('SCHEDULED', 'LIVE', 'COMPLETED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "NotificationKind" AS ENUM ('LEAGUE_FIXTURE_SCHEDULED', 'LEAGUE_MATCH_STARTED', 'LEAGUE_FIXTURE_RESULT', 'LEAGUE_TIEBREAK_SCHEDULED', 'LEAGUE_ROUND_DRAWN', 'LEAGUE_FINISHED');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "email" TEXT,
    "passwordHash" TEXT,
    "isGuest" BOOLEAN NOT NULL DEFAULT false,
    "role" "Role" NOT NULL DEFAULT 'PLAYER',
    "username" TEXT NOT NULL,
    "usernameLower" TEXT NOT NULL,
    "name" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "avatarId" TEXT,
    "avatarColor" TEXT,
    "imageUrl" TEXT,
    "isPublic" BOOLEAN NOT NULL DEFAULT true,
    "bio" TEXT,
    "github" TEXT,
    "linkedin" TEXT,
    "twitter" TEXT,
    "codeforces" TEXT,
    "leetcode" TEXT,
    "codechef" TEXT,
    "hackerrank" TEXT,
    "website" TEXT,
    "wins" INTEGER NOT NULL DEFAULT 0,
    "losses" INTEGER NOT NULL DEFAULT 0,
    "draws" INTEGER NOT NULL DEFAULT 0,
    "xp" INTEGER NOT NULL DEFAULT 0,
    "winStreak" INTEGER NOT NULL DEFAULT 0,
    "bestStreak" INTEGER NOT NULL DEFAULT 0,
    "lastBattleAt" TIMESTAMP(3),
    "rating" DOUBLE PRECISION NOT NULL DEFAULT 1500,
    "ratingRd" DOUBLE PRECISION NOT NULL DEFAULT 350,
    "ratingVolatility" DOUBLE PRECISION NOT NULL DEFAULT 0.06,
    "rankedBattles" INTEGER NOT NULL DEFAULT 0,
    "peakRating" DOUBLE PRECISION NOT NULL DEFAULT 1500,
    "upsetWins" INTEGER NOT NULL DEFAULT 0,
    "perfectWins" INTEGER NOT NULL DEFAULT 0,
    "easyWins" INTEGER NOT NULL DEFAULT 0,
    "mediumWins" INTEGER NOT NULL DEFAULT 0,
    "hardWins" INTEGER NOT NULL DEFAULT 0,
    "distinctProblemsWon" INTEGER NOT NULL DEFAULT 0,
    "approvedProblems" INTEGER NOT NULL DEFAULT 0,
    "signupOrdinal" INTEGER NOT NULL DEFAULT 0,
    "battlesToday" INTEGER NOT NULL DEFAULT 0,
    "xpDay" TEXT NOT NULL DEFAULT '',

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserBadge" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "badgeKey" TEXT NOT NULL,
    "earnedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "battleId" TEXT,
    "count" INTEGER NOT NULL DEFAULT 1,

    CONSTRAINT "UserBadge_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BadgeRule" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "rarity" TEXT NOT NULL,
    "artKey" TEXT NOT NULL,
    "glyph" TEXT NOT NULL,
    "conditions" JSONB NOT NULL,
    "progressFrom" INTEGER,
    "repeatEvery" INTEGER,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BadgeRule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RatingHistory" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "battleId" TEXT NOT NULL,
    "ratingBefore" DOUBLE PRECISION NOT NULL,
    "ratingAfter" DOUBLE PRECISION NOT NULL,
    "rdBefore" DOUBLE PRECISION NOT NULL,
    "rdAfter" DOUBLE PRECISION NOT NULL,
    "delta" DOUBLE PRECISION NOT NULL,
    "opponentRating" DOUBLE PRECISION,
    "score" DOUBLE PRECISION NOT NULL,
    "seasonId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RatingHistory_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Season" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "Season_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SeasonStanding" (
    "id" TEXT NOT NULL,
    "seasonId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "rank" INTEGER NOT NULL,
    "rating" DOUBLE PRECISION NOT NULL,
    "rd" DOUBLE PRECISION NOT NULL,
    "tier" TEXT NOT NULL,
    "wins" INTEGER NOT NULL,
    "losses" INTEGER NOT NULL,
    "rankedBattles" INTEGER NOT NULL,
    "xpEarned" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "SeasonStanding_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MatchQueueEntry" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "rating" DOUBLE PRECISION NOT NULL,
    "difficulty" "Difficulty" NOT NULL,
    "mode" "Mode" NOT NULL DEFAULT 'ONE_V_ONE',
    "enqueuedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MatchQueueEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Problem" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "statementMarkdown" TEXT NOT NULL,
    "constraints" TEXT NOT NULL,
    "difficulty" "Difficulty" NOT NULL,
    "allowedLanguages" TEXT[],
    "starterCode" JSONB NOT NULL,
    "timeLimitDefaultSec" INTEGER NOT NULL DEFAULT 600,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" "ProblemStatus" NOT NULL DEFAULT 'APPROVED',
    "authorId" TEXT,
    "reviewNote" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "reviewedById" TEXT,

    CONSTRAINT "Problem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TestCase" (
    "id" TEXT NOT NULL,
    "problemId" TEXT NOT NULL,
    "kind" "TestKind" NOT NULL,
    "input" TEXT NOT NULL,
    "expectedOutput" TEXT NOT NULL,
    "ordinal" INTEGER NOT NULL,
    "weight" INTEGER NOT NULL DEFAULT 1,

    CONSTRAINT "TestCase_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Battle" (
    "id" TEXT NOT NULL,
    "roomCode" TEXT NOT NULL,
    "mode" "Mode" NOT NULL,
    "difficulty" "Difficulty" NOT NULL,
    "timeLimitSec" INTEGER NOT NULL,
    "status" "BattleStatus" NOT NULL DEFAULT 'LOBBY',
    "seed" TEXT NOT NULL,
    "hostUserId" TEXT NOT NULL,
    "assignedProblemId" TEXT,
    "serverStartAt" TIMESTAMP(3),
    "serverEndAt" TIMESTAMP(3),
    "winnerSide" "Side",
    "finishReason" "FinishReason",
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "isRanked" BOOLEAN NOT NULL DEFAULT false,
    "seasonId" TEXT,

    CONSTRAINT "Battle_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Team" (
    "id" TEXT NOT NULL,
    "battleId" TEXT NOT NULL,
    "side" "Side" NOT NULL,

    CONSTRAINT "Team_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TeamMember" (
    "id" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "slot" INTEGER NOT NULL,
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TeamMember_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Submission" (
    "id" TEXT NOT NULL,
    "battleId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "teamSide" "Side" NOT NULL,
    "language" TEXT NOT NULL,
    "sourceCode" TEXT NOT NULL,
    "status" "SubmissionStatus" NOT NULL DEFAULT 'QUEUED',
    "passedCount" INTEGER NOT NULL DEFAULT 0,
    "totalCount" INTEGER NOT NULL DEFAULT 0,
    "perTestResults" JSONB,
    "runtimeMs" INTEGER NOT NULL DEFAULT 0,
    "errorMessage" TEXT,
    "submittedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "judgedAt" TIMESTAMP(3),

    CONSTRAINT "Submission_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Result" (
    "id" TEXT NOT NULL,
    "battleId" TEXT NOT NULL,
    "winnerSide" "Side",
    "reason" "FinishReason" NOT NULL,
    "decidingSubmissionId" TEXT,
    "standings" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Result_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PageView" (
    "id" TEXT NOT NULL,
    "path" TEXT NOT NULL,
    "visitorId" TEXT NOT NULL,
    "userId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PageView_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "League" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "logoUrl" TEXT,
    "joinCode" TEXT NOT NULL,
    "visibility" "LeagueVisibility" NOT NULL DEFAULT 'PUBLIC',
    "status" "LeagueStatus" NOT NULL DEFAULT 'OPEN',
    "teamSize" INTEGER NOT NULL DEFAULT 1,
    "maxTeams" INTEGER,
    "qualifyMode" "QualificationMode",
    "qualifyValue" INTEGER,
    "hostUserId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "finishedAt" TIMESTAMP(3),

    CONSTRAINT "League_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LeagueTeam" (
    "id" TEXT NOT NULL,
    "leagueId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "logoUrl" TEXT,
    "captainUserId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LeagueTeam_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LeagueTeamMember" (
    "id" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LeagueTeamMember_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LeagueFixture" (
    "id" TEXT NOT NULL,
    "leagueId" TEXT NOT NULL,
    "round" "LeagueRound" NOT NULL DEFAULT 'GROUP',
    "status" "FixtureStatus" NOT NULL DEFAULT 'SCHEDULED',
    "homeTeamId" TEXT NOT NULL,
    "awayTeamId" TEXT NOT NULL,
    "timeLimitSec" INTEGER NOT NULL DEFAULT 1800,
    "difficulty" "Difficulty" NOT NULL DEFAULT 'MEDIUM',
    "winnerTeamId" TEXT,
    "scheduledAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "LeagueFixture_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LeagueFixtureLeg" (
    "id" TEXT NOT NULL,
    "fixtureId" TEXT NOT NULL,
    "ordinal" INTEGER NOT NULL,
    "problemId" TEXT,
    "battleId" TEXT,
    "winnerTeamId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LeagueFixtureLeg_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Notification" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "kind" "NotificationKind" NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT,
    "link" TEXT,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Notification_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "User_usernameLower_key" ON "User"("usernameLower");

-- CreateIndex
CREATE INDEX "User_rating_idx" ON "User"("rating");

-- CreateIndex
CREATE INDEX "User_rankedBattles_idx" ON "User"("rankedBattles");

-- CreateIndex
CREATE INDEX "UserBadge_userId_idx" ON "UserBadge"("userId");

-- CreateIndex
CREATE INDEX "UserBadge_badgeKey_idx" ON "UserBadge"("badgeKey");

-- CreateIndex
CREATE UNIQUE INDEX "UserBadge_userId_badgeKey_key" ON "UserBadge"("userId", "badgeKey");

-- CreateIndex
CREATE UNIQUE INDEX "BadgeRule_key_key" ON "BadgeRule"("key");

-- CreateIndex
CREATE INDEX "BadgeRule_enabled_sortOrder_idx" ON "BadgeRule"("enabled", "sortOrder");

-- CreateIndex
CREATE INDEX "RatingHistory_userId_createdAt_idx" ON "RatingHistory"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "RatingHistory_battleId_idx" ON "RatingHistory"("battleId");

-- CreateIndex
CREATE UNIQUE INDEX "RatingHistory_userId_battleId_key" ON "RatingHistory"("userId", "battleId");

-- CreateIndex
CREATE INDEX "Season_isActive_idx" ON "Season"("isActive");

-- CreateIndex
CREATE INDEX "SeasonStanding_seasonId_rank_idx" ON "SeasonStanding"("seasonId", "rank");

-- CreateIndex
CREATE INDEX "SeasonStanding_userId_idx" ON "SeasonStanding"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "SeasonStanding_seasonId_userId_key" ON "SeasonStanding"("seasonId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX "MatchQueueEntry_userId_key" ON "MatchQueueEntry"("userId");

-- CreateIndex
CREATE INDEX "MatchQueueEntry_mode_difficulty_rating_idx" ON "MatchQueueEntry"("mode", "difficulty", "rating");

-- CreateIndex
CREATE INDEX "MatchQueueEntry_enqueuedAt_idx" ON "MatchQueueEntry"("enqueuedAt");

-- CreateIndex
CREATE INDEX "Problem_difficulty_idx" ON "Problem"("difficulty");

-- CreateIndex
CREATE INDEX "Problem_status_difficulty_idx" ON "Problem"("status", "difficulty");

-- CreateIndex
CREATE INDEX "Problem_authorId_status_idx" ON "Problem"("authorId", "status");

-- CreateIndex
CREATE INDEX "TestCase_problemId_kind_idx" ON "TestCase"("problemId", "kind");

-- CreateIndex
CREATE UNIQUE INDEX "Battle_roomCode_key" ON "Battle"("roomCode");

-- CreateIndex
CREATE INDEX "Battle_status_idx" ON "Battle"("status");

-- CreateIndex
CREATE INDEX "Battle_isRanked_status_idx" ON "Battle"("isRanked", "status");

-- CreateIndex
CREATE UNIQUE INDEX "Team_battleId_side_key" ON "Team"("battleId", "side");

-- CreateIndex
CREATE UNIQUE INDEX "TeamMember_teamId_slot_key" ON "TeamMember"("teamId", "slot");

-- CreateIndex
CREATE INDEX "Submission_battleId_submittedAt_idx" ON "Submission"("battleId", "submittedAt");

-- CreateIndex
CREATE UNIQUE INDEX "Result_battleId_key" ON "Result"("battleId");

-- CreateIndex
CREATE INDEX "PageView_createdAt_idx" ON "PageView"("createdAt");

-- CreateIndex
CREATE INDEX "PageView_visitorId_idx" ON "PageView"("visitorId");

-- CreateIndex
CREATE INDEX "PageView_path_idx" ON "PageView"("path");

-- CreateIndex
CREATE UNIQUE INDEX "League_joinCode_key" ON "League"("joinCode");

-- CreateIndex
CREATE INDEX "League_visibility_status_idx" ON "League"("visibility", "status");

-- CreateIndex
CREATE INDEX "League_hostUserId_idx" ON "League"("hostUserId");

-- CreateIndex
CREATE INDEX "LeagueTeam_leagueId_idx" ON "LeagueTeam"("leagueId");

-- CreateIndex
CREATE UNIQUE INDEX "LeagueTeam_leagueId_name_key" ON "LeagueTeam"("leagueId", "name");

-- CreateIndex
CREATE INDEX "LeagueTeamMember_userId_idx" ON "LeagueTeamMember"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "LeagueTeamMember_teamId_userId_key" ON "LeagueTeamMember"("teamId", "userId");

-- CreateIndex
CREATE INDEX "LeagueFixture_leagueId_round_idx" ON "LeagueFixture"("leagueId", "round");

-- CreateIndex
CREATE INDEX "LeagueFixture_leagueId_status_idx" ON "LeagueFixture"("leagueId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "LeagueFixtureLeg_battleId_key" ON "LeagueFixtureLeg"("battleId");

-- CreateIndex
CREATE INDEX "LeagueFixtureLeg_fixtureId_idx" ON "LeagueFixtureLeg"("fixtureId");

-- CreateIndex
CREATE UNIQUE INDEX "LeagueFixtureLeg_fixtureId_ordinal_key" ON "LeagueFixtureLeg"("fixtureId", "ordinal");

-- CreateIndex
CREATE INDEX "Notification_userId_readAt_idx" ON "Notification"("userId", "readAt");

-- CreateIndex
CREATE INDEX "Notification_userId_createdAt_idx" ON "Notification"("userId", "createdAt");

-- AddForeignKey
ALTER TABLE "UserBadge" ADD CONSTRAINT "UserBadge_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RatingHistory" ADD CONSTRAINT "RatingHistory_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SeasonStanding" ADD CONSTRAINT "SeasonStanding_seasonId_fkey" FOREIGN KEY ("seasonId") REFERENCES "Season"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SeasonStanding" ADD CONSTRAINT "SeasonStanding_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MatchQueueEntry" ADD CONSTRAINT "MatchQueueEntry_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Problem" ADD CONSTRAINT "Problem_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TestCase" ADD CONSTRAINT "TestCase_problemId_fkey" FOREIGN KEY ("problemId") REFERENCES "Problem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Battle" ADD CONSTRAINT "Battle_hostUserId_fkey" FOREIGN KEY ("hostUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Battle" ADD CONSTRAINT "Battle_assignedProblemId_fkey" FOREIGN KEY ("assignedProblemId") REFERENCES "Problem"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Team" ADD CONSTRAINT "Team_battleId_fkey" FOREIGN KEY ("battleId") REFERENCES "Battle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeamMember" ADD CONSTRAINT "TeamMember_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeamMember" ADD CONSTRAINT "TeamMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Submission" ADD CONSTRAINT "Submission_battleId_fkey" FOREIGN KEY ("battleId") REFERENCES "Battle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Submission" ADD CONSTRAINT "Submission_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Result" ADD CONSTRAINT "Result_battleId_fkey" FOREIGN KEY ("battleId") REFERENCES "Battle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "League" ADD CONSTRAINT "League_hostUserId_fkey" FOREIGN KEY ("hostUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueTeam" ADD CONSTRAINT "LeagueTeam_leagueId_fkey" FOREIGN KEY ("leagueId") REFERENCES "League"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueTeamMember" ADD CONSTRAINT "LeagueTeamMember_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "LeagueTeam"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueTeamMember" ADD CONSTRAINT "LeagueTeamMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueFixture" ADD CONSTRAINT "LeagueFixture_leagueId_fkey" FOREIGN KEY ("leagueId") REFERENCES "League"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueFixture" ADD CONSTRAINT "LeagueFixture_homeTeamId_fkey" FOREIGN KEY ("homeTeamId") REFERENCES "LeagueTeam"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueFixture" ADD CONSTRAINT "LeagueFixture_awayTeamId_fkey" FOREIGN KEY ("awayTeamId") REFERENCES "LeagueTeam"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueFixture" ADD CONSTRAINT "LeagueFixture_winnerTeamId_fkey" FOREIGN KEY ("winnerTeamId") REFERENCES "LeagueTeam"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueFixtureLeg" ADD CONSTRAINT "LeagueFixtureLeg_fixtureId_fkey" FOREIGN KEY ("fixtureId") REFERENCES "LeagueFixture"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueFixtureLeg" ADD CONSTRAINT "LeagueFixtureLeg_problemId_fkey" FOREIGN KEY ("problemId") REFERENCES "Problem"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LeagueFixtureLeg" ADD CONSTRAINT "LeagueFixtureLeg_battleId_fkey" FOREIGN KEY ("battleId") REFERENCES "Battle"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

