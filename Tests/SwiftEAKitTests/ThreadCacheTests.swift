import XCTest
@testable import SwiftEAKit

final class ThreadCacheTests: XCTestCase {

    // MARK: - Basic Operations

    func testPutAndGet() async {
        let cache = ThreadCache(maxSize: 10)

        let thread = Thread(id: "thread-1", subject: "Test Subject")
        await cache.put(thread)

        let retrieved = await cache.get("thread-1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "thread-1")
        XCTAssertEqual(retrieved?.subject, "Test Subject")
    }

    func testGetMissReturnsNil() async {
        let cache = ThreadCache(maxSize: 10)

        let retrieved = await cache.get("nonexistent")
        XCTAssertNil(retrieved)
    }

    func testContains() async {
        let cache = ThreadCache(maxSize: 10)

        let thread = Thread(id: "thread-1", subject: "Test")
        await cache.put(thread)

        let contains = await cache.contains("thread-1")
        let notContains = await cache.contains("thread-2")

        XCTAssertTrue(contains)
        XCTAssertFalse(notContains)
    }

    func testCount() async {
        let cache = ThreadCache(maxSize: 10)

        var count = await cache.count
        XCTAssertEqual(count, 0)

        await cache.put(Thread(id: "thread-1", subject: "Test 1"))
        count = await cache.count
        XCTAssertEqual(count, 1)

        await cache.put(Thread(id: "thread-2", subject: "Test 2"))
        count = await cache.count
        XCTAssertEqual(count, 2)
    }

    // MARK: - Cache Invalidation

    func testInvalidate() async {
        let cache = ThreadCache(maxSize: 10)

        await cache.put(Thread(id: "thread-1", subject: "Test"))
        var retrieved = await cache.get("thread-1")
        XCTAssertNotNil(retrieved)

        await cache.invalidate("thread-1")
        retrieved = await cache.get("thread-1")
        XCTAssertNil(retrieved)
    }

    func testInvalidateAll() async {
        let cache = ThreadCache(maxSize: 10)

        await cache.put(Thread(id: "thread-1", subject: "Test 1"))
        await cache.put(Thread(id: "thread-2", subject: "Test 2"))
        await cache.put(Thread(id: "thread-3", subject: "Test 3"))

        var count = await cache.count
        XCTAssertEqual(count, 3)

        await cache.invalidateAll()
        count = await cache.count
        XCTAssertEqual(count, 0)
    }

    func testInvalidateNonexistentDoesNothing() async {
        let cache = ThreadCache(maxSize: 10)

        await cache.put(Thread(id: "thread-1", subject: "Test"))
        await cache.invalidate("nonexistent")

        let count = await cache.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - Update Behavior

    func testPutUpdatesExistingEntry() async {
        let cache = ThreadCache(maxSize: 10)

        await cache.put(Thread(id: "thread-1", subject: "Original"))

        let original = await cache.get("thread-1")
        XCTAssertEqual(original?.subject, "Original")

        await cache.put(Thread(id: "thread-1", subject: "Updated", messageCount: 5))

        let updated = await cache.get("thread-1")
        XCTAssertEqual(updated?.subject, "Updated")
        XCTAssertEqual(updated?.messageCount, 5)

        // Should not increase count
        let count = await cache.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - LRU Eviction

    func testLRUEviction() async {
        let cache = ThreadCache(maxSize: 3)

        await cache.put(Thread(id: "thread-1", subject: "First"))
        await cache.put(Thread(id: "thread-2", subject: "Second"))
        await cache.put(Thread(id: "thread-3", subject: "Third"))

        var count = await cache.count
        XCTAssertEqual(count, 3)

        // Adding 4th should evict thread-1 (least recently used)
        await cache.put(Thread(id: "thread-4", subject: "Fourth"))

        count = await cache.count
        XCTAssertEqual(count, 3)

        let thread1 = await cache.get("thread-1")
        let thread2 = await cache.get("thread-2")
        let thread3 = await cache.get("thread-3")
        let thread4 = await cache.get("thread-4")

        XCTAssertNil(thread1)
        XCTAssertNotNil(thread2)
        XCTAssertNotNil(thread3)
        XCTAssertNotNil(thread4)
    }

    func testAccessUpdatesLRUOrder() async {
        let cache = ThreadCache(maxSize: 3)

        await cache.put(Thread(id: "thread-1", subject: "First"))
        await cache.put(Thread(id: "thread-2", subject: "Second"))
        await cache.put(Thread(id: "thread-3", subject: "Third"))

        // Access thread-1, making it most recently used
        _ = await cache.get("thread-1")

        // Adding 4th should now evict thread-2 (now least recently used)
        await cache.put(Thread(id: "thread-4", subject: "Fourth"))

        let thread1 = await cache.get("thread-1")
        let thread2 = await cache.get("thread-2")
        let thread3 = await cache.get("thread-3")
        let thread4 = await cache.get("thread-4")

        XCTAssertNotNil(thread1)
        XCTAssertNil(thread2)
        XCTAssertNotNil(thread3)
        XCTAssertNotNil(thread4)
    }

    // MARK: - Statistics

    func testHitCountIncrementsOnHit() async {
        let cache = ThreadCache(maxSize: 10)

        await cache.put(Thread(id: "thread-1", subject: "Test"))

        _ = await cache.get("thread-1")
        _ = await cache.get("thread-1")

        let hitCount = await cache.hitCount
        XCTAssertEqual(hitCount, 2)
    }

    func testMissCountIncrementsOnMiss() async {
        let cache = ThreadCache(maxSize: 10)

        _ = await cache.get("nonexistent-1")
        _ = await cache.get("nonexistent-2")

        let missCount = await cache.missCount
        XCTAssertEqual(missCount, 2)
    }

    func testHitRate() async {
        let cache = ThreadCache(maxSize: 10)

        await cache.put(Thread(id: "thread-1", subject: "Test"))

        // 3 hits
        _ = await cache.get("thread-1")
        _ = await cache.get("thread-1")
        _ = await cache.get("thread-1")

        // 1 miss
        _ = await cache.get("nonexistent")

        let hitRate = await cache.hitRate
        XCTAssertEqual(hitRate, 75.0, accuracy: 0.001)
    }

    func testHitRateZeroWhenNoAccess() async {
        let cache = ThreadCache(maxSize: 10)

        let hitRate = await cache.hitRate
        XCTAssertEqual(hitRate, 0.0)
    }

    func testResetStatistics() async {
        let cache = ThreadCache(maxSize: 10)

        await cache.put(Thread(id: "thread-1", subject: "Test"))
        _ = await cache.get("thread-1")
        _ = await cache.get("nonexistent")

        var hitCount = await cache.hitCount
        var missCount = await cache.missCount
        XCTAssertEqual(hitCount, 1)
        XCTAssertEqual(missCount, 1)

        await cache.resetStatistics()

        hitCount = await cache.hitCount
        missCount = await cache.missCount
        XCTAssertEqual(hitCount, 0)
        XCTAssertEqual(missCount, 0)
    }

    func testGetStatistics() async {
        let cache = ThreadCache(maxSize: 100)

        await cache.put(Thread(id: "thread-1", subject: "Test"))
        _ = await cache.get("thread-1")
        _ = await cache.get("nonexistent")

        let stats = await cache.getStatistics()

        XCTAssertEqual(stats.size, 1)
        XCTAssertEqual(stats.maxSize, 100)
        XCTAssertEqual(stats.hitCount, 1)
        XCTAssertEqual(stats.missCount, 1)
        XCTAssertEqual(stats.hitRate, 50.0, accuracy: 0.001)
    }

    func testStatisticsDescription() async {
        let cache = ThreadCache(maxSize: 100)

        await cache.put(Thread(id: "thread-1", subject: "Test"))
        _ = await cache.get("thread-1")
        _ = await cache.get("nonexistent")

        let stats = await cache.getStatistics()

        XCTAssertTrue(stats.description.contains("1/100 entries"))
        XCTAssertTrue(stats.description.contains("1 hits"))
        XCTAssertTrue(stats.description.contains("1 misses"))
        XCTAssertTrue(stats.description.contains("50.0% hit rate"))
    }

    // MARK: - Configuration

    func testDefaultMaxSize() {
        XCTAssertEqual(ThreadCache.defaultMaxSize, 500)
    }

    func testCustomMaxSize() async {
        let cache = ThreadCache(maxSize: 25)

        let maxSize = await cache.maxSize
        XCTAssertEqual(maxSize, 25)
    }

    func testMinimumMaxSizeIsOne() async {
        let cache = ThreadCache(maxSize: 0)

        let maxSize = await cache.maxSize
        XCTAssertEqual(maxSize, 1)
    }

    func testNegativeMaxSizeBecomesOne() async {
        let cache = ThreadCache(maxSize: -5)

        let maxSize = await cache.maxSize
        XCTAssertEqual(maxSize, 1)
    }

    // MARK: - Thread Safety

    func testConcurrentAccess() async {
        let cache = ThreadCache(maxSize: 100)

        // Pre-populate
        for i in 0..<50 {
            await cache.put(Thread(id: "thread-\(i)", subject: "Subject \(i)"))
        }

        // Concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 50..<100 {
                group.addTask {
                    await cache.put(Thread(id: "thread-\(i)", subject: "Subject \(i)"))
                }
            }

            // Readers
            for i in 0..<50 {
                group.addTask {
                    _ = await cache.get("thread-\(i)")
                }
            }

            // Invalidators
            for i in 20..<30 {
                group.addTask {
                    await cache.invalidate("thread-\(i)")
                }
            }
        }

        // Verify cache is still functional
        let count = await cache.count
        XCTAssertGreaterThan(count, 0)
    }

    // MARK: - Edge Cases

    func testSingleEntryCache() async {
        let cache = ThreadCache(maxSize: 1)

        await cache.put(Thread(id: "thread-1", subject: "First"))
        var thread1 = await cache.get("thread-1")
        XCTAssertNotNil(thread1)

        await cache.put(Thread(id: "thread-2", subject: "Second"))
        thread1 = await cache.get("thread-1")
        let thread2 = await cache.get("thread-2")
        XCTAssertNil(thread1)
        XCTAssertNotNil(thread2)

        let count = await cache.count
        XCTAssertEqual(count, 1)
    }

    func testThreadWithAllProperties() async {
        let cache = ThreadCache(maxSize: 10)

        let date = Date()
        let thread = Thread(
            id: "full-thread",
            subject: "Full Thread",
            participantCount: 5,
            messageCount: 10,
            firstDate: date.addingTimeInterval(-3600),
            lastDate: date,
            createdAt: date.addingTimeInterval(-7200),
            updatedAt: date
        )

        await cache.put(thread)

        let retrieved = await cache.get("full-thread")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "full-thread")
        XCTAssertEqual(retrieved?.subject, "Full Thread")
        XCTAssertEqual(retrieved?.participantCount, 5)
        XCTAssertEqual(retrieved?.messageCount, 10)
    }
}
