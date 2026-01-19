import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";
import { tx } from "@hirosystems/clarinet-sdk";

const accounts = simnet.getAccounts();
const OWNER = accounts.get("deployer")!;
const ALICE = accounts.get("wallet_1")!;
const BOB = accounts.get("wallet_2")!;
const CHARLIE = accounts.get("wallet_3")!;
const CONTRACT = "origo";
const MAX_DAILY_ATTESTATIONS = 10;
const LIMIT_TAGS = Array.from(
  { length: MAX_DAILY_ATTESTATIONS + 1 },
  (_, index) => `limit-tag-${index}`,
);

const ownerPrincipal = Cl.standardPrincipal(OWNER);
const alicePrincipal = Cl.standardPrincipal(ALICE);
const bobPrincipal = Cl.standardPrincipal(BOB);
const charliePrincipal = Cl.standardPrincipal(CHARLIE);

async function initializeContract(sender = OWNER) {
  const [receipt] = await simnet.mineBlock([
    tx.callPublicFn(CONTRACT, "initialize", [], sender),
  ]);
  expect(receipt.result).toBeOk(Cl.bool(true));
}

async function registerUser(account: string) {
  const [receipt] = await simnet.mineBlock([
    tx.callPublicFn(CONTRACT, "register", [], account),
  ]);
  expect(receipt.result).toBeOk(Cl.bool(true));
}

async function addTag(name: string, multiplier = 1) {
  const [receipt] = await simnet.mineBlock([
    tx.callPublicFn(
      CONTRACT,
      "add-tag-with-weight",
      [Cl.stringAscii(name), Cl.uint(multiplier)],
      OWNER,
    ),
  ]);
  expect(receipt.result).toBeOk(Cl.stringAscii(name));
}

describe("Origo core flows", () => {
  it("initializes once, stores the owner, and blocks repeats", async () => {
    await initializeContract();

    const ownerResult = await simnet.callReadOnlyFn(CONTRACT, "get-contract-owner", [], OWNER);
    expect(ownerResult.result).toBeOk(ownerPrincipal);

    const adminResult = await simnet.callReadOnlyFn(
      CONTRACT,
      "is-user-admin",
      [ownerPrincipal],
      OWNER,
    );
    expect(adminResult.result).toBeBool(true);

    const [retry] = await simnet.mineBlock([
      tx.callPublicFn(CONTRACT, "initialize", [], OWNER),
    ]);
    expect(retry.result).toBeErr(Cl.uint(401));
  });

  it("allows owner to add and remove admins", async () => {
    await initializeContract();

    const [addResult] = await simnet.mineBlock([
      tx.callPublicFn(CONTRACT, "add-admin", [charliePrincipal], OWNER),
    ]);
    expect(addResult.result).toBeOk(Cl.bool(true));

    const adminCheck = await simnet.callReadOnlyFn(
      CONTRACT,
      "is-user-admin",
      [charliePrincipal],
      OWNER,
    );
    expect(adminCheck.result).toBeBool(true);

    const [removeResult] = await simnet.mineBlock([
      tx.callPublicFn(CONTRACT, "remove-admin", [charliePrincipal], OWNER),
    ]);
    expect(removeResult.result).toBeOk(Cl.bool(true));

    const removed = await simnet.callReadOnlyFn(
      CONTRACT,
      "is-user-admin",
      [charliePrincipal],
      OWNER,
    );
    expect(removed.result).toBeBool(false);
  });

  it("registers users and exposes helper getters", async () => {
    await initializeContract();
    await registerUser(ALICE);

    const registered = await simnet.callReadOnlyFn(
      CONTRACT,
      "is-registered",
      [alicePrincipal],
      ALICE,
    );
    expect(registered.result).toBeBool(true);

    const notRegistered = await simnet.callReadOnlyFn(
      CONTRACT,
      "is-registered",
      [bobPrincipal],
      BOB,
    );
    expect(notRegistered.result).toBeBool(false);

    const totalReputation = await simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-total-reputation",
      [alicePrincipal],
      ALICE,
    );
    expect(totalReputation.result).toBeOk(Cl.uint(0));

    const dailyCount = await simnet.callReadOnlyFn(
      CONTRACT,
      "get-daily-attestation-count",
      [alicePrincipal],
      ALICE,
    );
    expect(dailyCount.result).toBeOk(Cl.uint(0));
  });

  it("records weighted attestations with tagging guards", async () => {
    await initializeContract();
    await registerUser(ALICE);
    await registerUser(BOB);
    const tag = "mentor";
    await addTag(tag, 2);

    const [attestResult] = await simnet.mineBlock([
      tx.callPublicFn(CONTRACT, "attest", [bobPrincipal, Cl.stringAscii(tag)], ALICE),
    ]);
    expect(attestResult.result).toBeOk(Cl.bool(true));

    const hasAttested = await simnet.callReadOnlyFn(
      CONTRACT,
      "has-attested",
      [alicePrincipal, bobPrincipal, Cl.stringAscii(tag)],
      ALICE,
    );
    expect(hasAttested.result).toBeBool(true);

    const reputation = await simnet.callReadOnlyFn(
      CONTRACT,
      "get-reputation",
      [bobPrincipal, Cl.stringAscii(tag)],
      ALICE,
    );
    expect(reputation.result).toBeOk(Cl.uint(1));

    const weighted = await simnet.callReadOnlyFn(
      CONTRACT,
      "get-weighted-reputation",
      [bobPrincipal, Cl.stringAscii(tag)],
      ALICE,
    );
    expect(weighted.result).toBeOk(Cl.uint(2));

    const totalReputation = await simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-total-reputation",
      [bobPrincipal],
      ALICE,
    );
    expect(totalReputation.result).toBeOk(Cl.uint(2));

    const attestationWeight = await simnet.callReadOnlyFn(
      CONTRACT,
      "get-attestation-weight",
      [alicePrincipal, bobPrincipal, Cl.stringAscii(tag)],
      ALICE,
    );
    expect(attestationWeight.result).toBeOk(Cl.some(Cl.uint(2)));

    const duplicateAttempt = await simnet.mineBlock([
      tx.callPublicFn(CONTRACT, "attest", [bobPrincipal, Cl.stringAscii(tag)], ALICE),
    ]);
    expect(duplicateAttempt[0].result).toBeErr(Cl.uint(404));

    const selfAttempt = await simnet.mineBlock([
      tx.callPublicFn(CONTRACT, "attest", [alicePrincipal, Cl.stringAscii(tag)], ALICE),
    ]);
    expect(selfAttempt[0].result).toBeErr(Cl.uint(403));
  });

  it("enforces the daily attestation limit", async () => {
    await initializeContract();
    await registerUser(ALICE);
    await registerUser(BOB);
    for (const tag of LIMIT_TAGS) {
      await addTag(tag, 1);
    }

    for (let index = 0; index < LIMIT_TAGS.length; index += 1) {
      const tagName = LIMIT_TAGS[index];
      const [result] = await simnet.mineBlock([
        tx.callPublicFn(CONTRACT, "attest", [bobPrincipal, Cl.stringAscii(tagName)], ALICE),
      ]);
      if (index < MAX_DAILY_ATTESTATIONS) {
        expect(result.result).toBeOk(Cl.bool(true));
      } else {
        expect(result.result).toBeErr(Cl.uint(416));
      }
    }
  });

  it("allows admins to slash weighted reputation", async () => {
    await initializeContract();
    await registerUser(ALICE);
    await registerUser(BOB);
    const tag = "guide";
    await addTag(tag, 2);

    const [attestResult] = await simnet.mineBlock([
      tx.callPublicFn(CONTRACT, "attest", [bobPrincipal, Cl.stringAscii(tag)], ALICE),
    ]);
    expect(attestResult.result).toBeOk(Cl.bool(true));

    const [slashResult] = await simnet.mineBlock([
      tx.callPublicFn(CONTRACT, "slash", [bobPrincipal, Cl.stringAscii(tag)], OWNER),
    ]);
    expect(slashResult.result).toBeOk(Cl.bool(true));

    const postCount = await simnet.callReadOnlyFn(
      CONTRACT,
      "get-reputation",
      [bobPrincipal, Cl.stringAscii(tag)],
      ALICE,
    );
    expect(postCount.result).toBeOk(Cl.uint(0));

    const postWeighted = await simnet.callReadOnlyFn(
      CONTRACT,
      "get-weighted-reputation",
      [bobPrincipal, Cl.stringAscii(tag)],
      ALICE,
    );
    expect(postWeighted.result).toBeOk(Cl.uint(1));

    const postTotal = await simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-total-reputation",
      [bobPrincipal],
      ALICE,
    );
    expect(postTotal.result).toBeOk(Cl.uint(1));
  });
});
