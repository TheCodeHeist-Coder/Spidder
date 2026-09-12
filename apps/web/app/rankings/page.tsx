"use client";

import { useEffect, useState } from "react";
import type {
  BadgeView,
  LeaderboardBoard,
  LeaderboardEntry,
  LeaderboardResponse,
} from "@repo/protocol";
import { rankFor } from "@repo/game";
import { AppShell } from "../../components/AppShell";
import { Spinner } from "../../components/atoms";
import { Badge } from "../../components/ranking/Badges";
import { fetchLeaderboard } from "../../lib/api";
import { useSession } from "../../lib/useSession";
import { useProfile } from "../../lib/useProfile";
import {
  NameStack,
  ProfileLink,
  UserAvatar,
} from "../../components/identity/UserIdentity";

/**
 * The ladder.
 *
 * Two boards, because "who is best" and "who has played most" are different
 * questions and one number cannot honestly answer both:
 *
 *   Rating  Glicko-2. Zero-sum, moves only in matchmade battles, and can fall.
 *   XP      Career volume. Rises only, so it rewards showing up.
 *
 * Rating is the default because it is the one that means something.
 */
export default function RankingsPage() {
  const { session } = useSession();
  const { profile } = useProfile(session);

  const [board, setBoard] = useState<LeaderboardBoard>("rating");
  const [data, setData] = useState<LeaderboardResponse | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    setData(null);
    setFailed(false);
    fetchLeaderboard(session?.token, board)
      .then((d) => active && setData(d))
      .catch(() => active && setFailed(true));
    return () => {
      active = false;
    };
  }, [session?.token, board]);

  /*
   * The board splits in two.
   *
   * A leaderboard's job is to answer "who is winning" before it answers "where
   * am I", and a uniform table answers neither quickly — rank 1 and rank 40
   * look identical, so the eye has to read rather than glance. The top three
   * get cards; everyone else keeps the dense table, which is the right shape
   * for scanning a long list.
   *
   * Split only when there are enough entries to be worth it: a podium of two
   * with an empty table beneath reads as a rendering fault, not a design.
   */
  const PODIUM_MIN = 3;
  const entries = data?.entries ?? [];
  const podium = entries.length >= PODIUM_MIN ? entries.slice(0, 3) : [];
  const rest = entries.length >= PODIUM_MIN ? entries.slice(3) : entries;

  const outsidePage =
    data?.me && !data.entries.some((e) => e.userId === data.me?.userId)
      ? data.me
      : null;

  return (
    <AppShell session={session} profile={profile}>
      <div className="mx-auto w-full max-w-4xl px-5 py-8 sm:px-7">
        <h1 className="mt-2 wordmark  text-2xl font-bold uppercase tracking-wide">
          Rankings
        </h1>
        <p
          className="mt-2 max-w-2xl font-mono text-[0.8rem] leading-relaxed"
          style={{ color: "var(--color-ink-dim)" }}
        >
          {board === "rating"
            ? "Skill rating from ranked battles only. It moves both ways, and a rating is withheld until enough battles have been fought to be sure of it."
            : "Career XP — how much you have fought. Earned in every battle, ranked or not."}
        </p>

        <div className="mt-5 flex gap-1.5">
          <BoardTab
            active={board === "rating"}
            onClick={() => setBoard("rating")}
            label="Rating"
          />
          <BoardTab
            active={board === "xp"}
            onClick={() => setBoard("xp")}
            label="Career XP"
          />
        </div>

        {failed ? (
          <p
            className="panel mt-6 p-5 font-mono text-[0.8rem]"
            style={{ color: "var(--color-bad)" }}
          >
            Could not load the leaderboard.
          </p>
        ) : !data ? (
          <div className="mt-8 flex justify-center">
            <Spinner />
          </div>
        ) : data.entries.length === 0 ? (
          <p
            className="panel mt-6 p-5 font-mono text-[0.8rem]"
            style={{ color: "var(--color-ink-faint)" }}
          >
            {board === "rating"
              ? "No placed operatives yet — ranked battles decide this board."
              : "No ranked operatives yet — finish a battle to appear here."}
          </p>
        ) : (
          <>
            {/*
              The podium: second, FIRST, third — the winner in the middle.

              The cards are laid out on a shared bottom edge and given
              different top padding, so first place stands taller than the
              other two exactly as a real podium does.

              Source order stays 1, 2, 3 and CSS `order` does the arranging.
              That matters twice over: a screen reader and the keyboard tab
              sequence still meet the winner first, and when the row collapses
              to a single column on a phone the ordering is dropped, so the
              stack reads 1, 2, 3 top to bottom rather than stranding the
              winner in the middle with no height cue to explain why.
            */}
            {podium.length > 0 && (
              <div className="mt-8 flex flex-col gap-3 sm:grid sm:grid-cols-3 sm:items-end sm:gap-4">
                {podium.map((e) => (
                  <PodiumCard
                    key={e.userId}
                    entry={e}
                    board={board}
                    isMe={e.userId === session?.userId}
                  />
                ))}
              </div>
            )}

            {rest.length > 0 && (
              <div className="panel mt-4 overflow-x-auto">
                <table className="w-full border-collapse">
                  <thead>
                    <tr style={{ background: "var(--color-surface-2)" }}>
                      <Th width="3.5rem">#</Th>
                      <Th>Operative</Th>
                      <Th width="9rem">Badges</Th>
                      <Th>{board === "rating" ? "Tier" : "Rank"}</Th>
                      <Th align="right">
                        {board === "rating" ? "Rating" : "XP"}
                      </Th>
                      <Th align="right">W/L</Th>
                      <Th align="right">Streak</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {rest.map((e) => (
                      <Row
                        key={e.userId}
                        entry={e}
                        board={board}
                        isMe={e.userId === session?.userId}
                      />
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}

        {/*
          Signed in but not on the board yet. Saying so beats silently omitting
          them, which reads as a bug rather than a rule.
        */}
        {data?.meProvisional && (
          <p
            className="panel mt-4 p-4 font-mono text-[0.76rem]"
            style={{ color: "var(--color-ink-faint)" }}
          >
            You are still placing. Finish a few more ranked battles and your
            rating will appear here.
          </p>
        )}

        {outsidePage && (
          <>
            <p className="label mt-6">Your standing</p>
            <div className="panel mt-2 overflow-x-auto">
              {/* Same column widths as the board above, so the two line up
                  rather than reading as an unrelated stray row. */}
              <table className="w-full border-collapse">
                <colgroup>
                  <col style={{ width: "3.5rem" }} />
                  <col />
                  <col style={{ width: "9rem" }} />
                  <col />
                  <col />
                  <col />
                  <col />
                </colgroup>
                <tbody>
                  <Row entry={outsidePage} board={board} isMe />
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </AppShell>
  );
}

function BoardTab({
  active,
  onClick,
  label,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      className="rounded-[7px] border px-3.5 py-1.5 font-mono text-[0.72rem] font-bold uppercase tracking-wide transition-colors"
      style={{
        borderColor: active ? "var(--color-primary)" : "var(--color-line)",
        background: active
          ? "color-mix(in srgb, var(--color-primary) 14%, transparent)"
          : "transparent",
        color: active ? "var(--color-primary)" : "var(--color-ink-faint)",
      }}
      aria-pressed={active}
    >
      {label}
    </button>
  );
}

function Th({
  children,
  align = "left",
  width,
}: {
  children: React.ReactNode;
  align?: "left" | "right";
  /** Fixed column width, so the badge and rank columns stop shifting. */
  width?: string;
}) {
  return (
    <th
      className="label border-b px-4 py-2.5"
      style={{ borderColor: "var(--color-line)", textAlign: align, width }}
    >
      {children}
    </th>
  );
}

function Row({
  entry,
  board,
  isMe,
}: {
  entry: LeaderboardEntry;
  board: LeaderboardBoard;
  isMe: boolean;
}) {
  const xpRank = rankFor(entry.xp);
  return (
    <tr style={{ background: isMe ? "var(--color-surface-2)" : undefined }}>
      <Td>
        <span
          className="font-bold"
          style={{
            color:
              entry.rank <= 3 ? "var(--color-accent)" : "var(--color-ink-faint)",
          }}
        >
          {String(entry.rank).padStart(2, "0")}
        </span>
      </Td>
      <Td>
        <span className="flex items-center gap-2.5">
          <ProfileLink
            username={entry.username}
            className="flex min-w-0 items-center gap-2.5"
          >
            <UserAvatar identity={entry} size={30} rounded={7} />
            <NameStack identity={entry} usernameClassName="font-semibold" />
          </ProfileLink>
          {isMe && <span className="label">you</span>}
        </span>
      </Td>
      {/*
        Badges get their own column rather than sitting under the name.
        Stacked, they made every row a different height and pushed the
        username off the row's centre line; beside it, the medals line up
        down the page and the name column stays a clean left edge.
      */}
      <Td>
        <MedalStrip badges={entry.badges} />
      </Td>
      <Td>
        <span style={{ color: "var(--color-ink-dim)" }}>
          {board === "rating"
            ? entry.rating.tierLabel ?? "Unranked"
            : xpRank.label}
        </span>
      </Td>
      <Td align="right">
        <span className="font-bold">
          {board === "rating" ? entry.rating.rating : entry.xp}
        </span>
      </Td>
      <Td align="right">
        {entry.wins}/{entry.losses}
      </Td>
      <Td align="right">{entry.bestStreak}</Td>
    </tr>
  );
}

function Td({
  children,
  align = "left",
}: {
  children: React.ReactNode;
  align?: "left" | "right";
}) {
  return (
    <td
      className="border-b px-4 py-3 font-mono text-[0.82rem] tabular-nums"
      style={{ borderColor: "var(--color-line)", textAlign: align }}
    >
      {children}
    </td>
  );
}

/**
 * A tight horizontal run of medals for a table row.
 *
 * Not `BadgeRow`: that renders each medal as a `<figure>` padded to
 * `width: size + 16`, which is right on a profile shelf but leaves 16px of
 * dead space per badge in a table — enough that two rows with different badge
 * counts no longer line up. Here the medals butt together at a fixed size and
 * the column keeps a straight left edge.
 *
 * Capped at three. The API already sends only the rarest few, but a cap means
 * the column can never widen enough to squeeze the name beside it.
 */
const MEDALS_SHOWN = 3;

function MedalStrip({
  badges,
  size = 26,
}: {
  badges: BadgeView[];
  size?: number;
}) {
  if (badges.length === 0) {
    return (
      <span
        className="font-mono text-[0.72rem]"
        style={{ color: "var(--color-ink-ghost)" }}
      >
        —
      </span>
    );
  }

  const shown = badges.slice(0, MEDALS_SHOWN);
  const extra = badges.length - shown.length;

  return (
    <span className="flex items-center gap-1.5">
      {shown.map((b) => (
        <MedalDot key={b.key} badge={b} size={size} />
      ))}
      {extra > 0 && (
        <span
          className="font-mono text-[0.68rem]"
          style={{ color: "var(--color-ink-faint)" }}
        >
          +{extra}
        </span>
      )}
    </span>
  );
}

/** One medal at an exact pixel size, with its meaning on hover. */
function MedalDot({ badge, size }: { badge: BadgeView; size: number }) {
  return (
    <span className="inline-flex shrink-0">
      <Badge badge={badge} bare={size} />
    </span>
  );
}

/**
 * One of the top three, as a card.
 *
 * ORDER AND HEIGHT
 * ----------------
 * A real podium: second, FIRST, third, with the winner raised above the other
 * two. The parent aligns all three on a shared bottom edge, and the extra
 * height comes from top padding here rather than a fixed height, so a long
 * username wrapping to two lines grows the card instead of overflowing it.
 *
 * `order` only applies once the row is a grid (sm and up). Stacked on a phone
 * the cards fall back to source order — 1, 2, 3 — because the height cue that
 * justifies a centred winner does not survive stacking.
 *
 * EVERY CARD IS THE SAME SHAPE
 * ----------------------------
 * Avatar, name, headline number, then a fixed-height medal strip. The strip
 * keeps its height whether or not the holder has badges, so three cards with
 * different badge counts still have their numbers on one line — the exact
 * misalignment that made the old rows look untidy.
 */
const PLACE_TONE: Record<number, { rim: string; chip: string; ink: string }> = {
  1: { rim: "#e0b341", chip: "#e0b341", ink: "#1a1205" },
  2: { rim: "#b9c2cc", chip: "#b9c2cc", ink: "#12161a" },
  3: { rim: "#c98b5e", chip: "#c98b5e", ink: "#1a1008" },
};

function PodiumCard({
  entry,
  board,
  isMe,
}: {
  entry: LeaderboardEntry;
  board: LeaderboardBoard;
  isMe: boolean;
}) {
  const tone = PLACE_TONE[entry.rank] ?? PLACE_TONE[3]!;
  const first = entry.rank === 1;
  const xpRank = rankFor(entry.xp);
  const value = board === "rating" ? entry.rating.rating : entry.xp;
  const sub =
    board === "rating" ? entry.rating.tierLabel ?? "Unranked" : xpRank.label;

  // 2 · 1 · 3 across the row, first place raised above the other two.
  const order = first ? "sm:order-2" : entry.rank === 2 ? "sm:order-1" : "sm:order-3";
  const lift = first ? "sm:pt-10 sm:pb-6" : "sm:pt-7 sm:pb-4";

  return (
    <div
      className={`relative flex flex-col items-center rounded-[12px] border px-3 pb-4 pt-7 text-center sm:px-4 ${order} ${lift}`}
      style={{
        borderColor: first ? tone.rim : "var(--color-line-strong)",
        background: isMe
          ? "var(--color-surface-2)"
          : "var(--color-surface-1)",
        boxShadow: first
          ? `0 10px 30px -18px ${tone.rim}, inset 0 1px 0 rgba(255,255,255,0.04)`
          : "inset 0 1px 0 rgba(255,255,255,0.03)",
      }}
    >
      {/* Rank chip, straddling the top edge so it reads as a seal. */}
      <span
        className="absolute -top-3 grid h-7 w-7 place-items-center rounded-full font-mono text-[0.78rem] font-bold"
        style={{ background: tone.chip, color: tone.ink }}
      >
        {entry.rank}
      </span>

      <ProfileLink
        username={entry.username}
        className="flex flex-col items-center gap-2"
      >
        <UserAvatar
          identity={entry}
          size={first ? 60 : 50}
          rounded={12}
        />
        <span className="flex min-w-0 max-w-full flex-col leading-tight">
          <span className="truncate text-[0.9rem] font-semibold">
            {entry.username}
          </span>
          {entry.name && (
            <span
              className="truncate font-mono text-[0.66rem]"
              style={{ color: "var(--color-ink-faint)" }}
            >
              {entry.name}
            </span>
          )}
        </span>
      </ProfileLink>

      {isMe && <span className="label mt-1">you</span>}

      <span
        className="mt-2.5 font-mono text-[1.4rem] font-bold leading-none tabular-nums"
        style={{ color: first ? tone.rim : "var(--color-ink)" }}
      >
        {value}
      </span>
      <span
        className="mt-1 font-mono text-[0.66rem] uppercase tracking-wider"
        style={{ color: "var(--color-ink-faint)" }}
      >
        {board === "rating" ? "rating" : "xp"} · {sub}
      </span>

      {/* Fixed height whether or not there are medals, so the three cards
          keep a common baseline. */}
      <span className="mt-3 flex h-[30px] items-center justify-center">
        <MedalStrip badges={entry.badges} size={26} />
      </span>

      <span
        className="mt-2 font-mono text-[0.68rem]"
        style={{ color: "var(--color-ink-dim)" }}
      >
        {entry.wins}W · {entry.losses}L · {entry.bestStreak} streak
      </span>
    </div>
  );
}
