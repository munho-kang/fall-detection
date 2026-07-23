// queue.js 오프라인 큐의 적재·재전송 규칙 검증

import { describe, expect, it, vi } from "vitest";

import { createFallQueue } from "../js/queue.js";

function fakeStorage() {
  const map = new Map();
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
  };
}

describe("fall queue", () => {
  it("적재한 낙상은 storage에 남아 새 페이지 로드에도 유지된다", () => {
    const storage = fakeStorage();
    createFallQueue(storage).enqueue({ room_name: "안방", room_number: 1 });

    // 같은 storage로 다시 만들어도(새 페이지 로드) 큐가 살아 있어야 한다
    expect(createFallQueue(storage).size()).toBe(1);
  });

  it("flush 성공 시 전부 순서대로 보내고 큐를 비운다", async () => {
    const q = createFallQueue(fakeStorage());
    q.enqueue({ id: 1 });
    q.enqueue({ id: 2 });

    const sent = [];
    await q.flush(async (p) => sent.push(p.id));

    expect(sent).toEqual([1, 2]);
    expect(q.size()).toBe(0);
  });

  it("postFn이 resolve하면(201 신규든 200 중복이든) 성공으로 보고 제거한다", async () => {
    const q = createFallQueue(fakeStorage());
    q.enqueue({ id: 1 });

    await q.flush(async () => ({ id: 1 })); // 서버가 중복(200)으로 답한 경우

    expect(q.size()).toBe(0);
  });

  it("실패하면 중단하고 실패 항목부터 순서를 보존한다", async () => {
    const q = createFallQueue(fakeStorage());
    q.enqueue({ id: 1 });
    q.enqueue({ id: 2 });
    q.enqueue({ id: 3 });

    const postFn = vi.fn(async (p) => {
      if (p.id === 2) throw new Error("서버 다운");
    });
    await q.flush(postFn);

    expect(postFn.mock.calls.map(([p]) => p.id)).toEqual([1, 2]); // 3은 시도조차 안 한다
    expect(q.size()).toBe(2);

    const sent = [];
    await q.flush(async (p) => sent.push(p.id)); // 다음 트리거에서 이어서
    expect(sent).toEqual([2, 3]);
  });

  it("flush가 겹쳐 불려도 이중 전송하지 않는다", async () => {
    const q = createFallQueue(fakeStorage());
    q.enqueue({ id: 1 });

    let release;
    const first = q.flush(() => new Promise((r) => (release = r)));
    await q.flush(async () => {
      throw new Error("재진입이면 불리면 안 된다");
    });

    release();
    await first;
    expect(q.size()).toBe(0);
  });
});
