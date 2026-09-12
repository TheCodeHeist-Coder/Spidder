import "dotenv/config";
import { defineConfig } from "prisma/config";

/**
 * Prisma 7 configuration. The datasource URL and seed command live here now
 * (the `datasource.url` field and package.json `prisma.seed` key were removed
 * in v7).
 *
 * The URL is read with `process.env` rather than prisma's `env()` helper on
 * purpose. `env()` resolves eagerly while the config file is being loaded and
 * THROWS if the variable is missing — which breaks `prisma generate`, a purely
 * offline codegen step that never opens a connection. CI has no DATABASE_URL
 * (the .env is gitignored), so every job that generated the client died on
 * `PrismaConfigEnvError` before compiling a single file.
 *
 * Empty string keeps the field well-typed when unset. Commands that genuinely
 * need a database — migrate, seed, studio — still fail loudly on connect, which
 * is the right place for that error; codegen no longer does.
 */
export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
    seed: "tsx prisma/seed.ts",
  },
  datasource: {
    url: process.env.DATABASE_URL ?? "",
  },
});
