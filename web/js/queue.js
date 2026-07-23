// 전송 실패한 낙상을 localStorage에 쌓아 두었다가 재전송하는 오프라인 큐 (순수 모듈)
//
// 서버의 unique 제약 + 200 응답이 재전송 중복을 흡수하므로, 여기서는 "성공하면 제거,
// 실패하면 순서 보존을 위해 중단"만 지키면 된다.

const KEY = "fall_queue";

export function createFallQueue(storage) {
  const read = () => {
    try {
      const items = JSON.parse(storage.getItem(KEY) ?? "[]");
      return Array.isArray(items) ? items : [];
    } catch {
      return []; // 깨진 값은 빈 큐로 취급한다
    }
  };
  const write = (items) => storage.setItem(KEY, JSON.stringify(items));

  let flushing = false;

  return {
    size: () => read().length,

    enqueue(payload) {
      write([...read(), payload]);
    },

    // 앞에서부터 하나씩 보낸다. postFn이 resolve하면(201 신규·200 중복 모두) 제거하고,
    // reject하면 그 자리에서 중단한다 — 다음 트리거(online·60초 주기 등)에서 재개된다.
    async flush(postFn) {
      if (flushing) return; // 트리거가 겹쳐도 이중 전송하지 않는다
      flushing = true;
      try {
        while (read().length > 0) {
          const [head] = read();
          try {
            await postFn(head);
          } catch {
            return;
          }
          // await 중 enqueue된 항목을 잃지 않도록, 성공 후 최신 큐에서 head만 제거한다.
          // 다른 탭이 같은 head를 먼저 제거했으면 건너뛴다 — 이중 제거로 인한 유실 방지.
          // 중복 전송은 서버의 unique 제약이 200으로 흡수한다.
          const current = read();
          if (JSON.stringify(current[0]) === JSON.stringify(head)) write(current.slice(1));
        }
      } finally {
        flushing = false;
      }
    },
  };
}
