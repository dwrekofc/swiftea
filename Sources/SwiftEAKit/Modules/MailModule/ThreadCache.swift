// ThreadCache - LRU cache for thread metadata to improve lookup performance

import Foundation

/// A thread-safe LRU cache for Thread objects.
///
/// This cache improves performance by storing recently accessed thread metadata
/// in memory, avoiding repeated database queries for frequently accessed threads.
///
/// Features:
/// - Configurable maximum size (bounded memory usage)
/// - LRU (Least Recently Used) eviction policy
/// - Thread-safe access via actor isolation
/// - Cache invalidation on thread modification
public actor ThreadCache {

    /// Cache entry containing the thread and access metadata
    private struct CacheEntry {
        let thread: Thread
        var lastAccessed: Date

        init(thread: Thread) {
            self.thread = thread
            self.lastAccessed = Date()
        }

        mutating func touch() {
            lastAccessed = Date()
        }
    }

    /// The maximum number of threads to cache
    public nonisolated let maxSize: Int

    /// The internal cache storage
    private var cache: [String: CacheEntry] = [:]

    /// Order of keys by access time (most recent at the end)
    private var accessOrder: [String] = []

    /// Statistics for monitoring cache performance
    public private(set) var hitCount: Int = 0
    public private(set) var missCount: Int = 0

    /// Default cache size
    public static let defaultMaxSize = 500

    /// Creates a new ThreadCache with the specified maximum size.
    ///
    /// - Parameter maxSize: Maximum number of threads to cache. Defaults to 500.
    public init(maxSize: Int = ThreadCache.defaultMaxSize) {
        self.maxSize = max(1, maxSize) // Ensure at least 1 entry
    }

    // MARK: - Cache Operations

    /// Get a thread from the cache.
    ///
    /// - Parameter id: The thread ID to look up
    /// - Returns: The cached Thread if found, nil otherwise
    public func get(_ id: String) -> Thread? {
        if var entry = cache[id] {
            hitCount += 1
            entry.touch()
            cache[id] = entry
            updateAccessOrder(id)
            return entry.thread
        }
        missCount += 1
        return nil
    }

    /// Store a thread in the cache.
    ///
    /// If the cache is at capacity, the least recently used entry is evicted.
    ///
    /// - Parameter thread: The thread to cache
    public func put(_ thread: Thread) {
        let id = thread.id

        // If already in cache, update it
        if cache[id] != nil {
            cache[id] = CacheEntry(thread: thread)
            updateAccessOrder(id)
            return
        }

        // Evict if at capacity
        while cache.count >= maxSize {
            evictLRU()
        }

        // Add new entry
        cache[id] = CacheEntry(thread: thread)
        accessOrder.append(id)
    }

    /// Invalidate (remove) a thread from the cache.
    ///
    /// Call this when a thread is modified to ensure stale data isn't served.
    ///
    /// - Parameter id: The thread ID to invalidate
    public func invalidate(_ id: String) {
        cache.removeValue(forKey: id)
        accessOrder.removeAll { $0 == id }
    }

    /// Invalidate all threads in the cache.
    public func invalidateAll() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    /// Check if a thread is in the cache.
    ///
    /// - Parameter id: The thread ID to check
    /// - Returns: true if the thread is cached
    public func contains(_ id: String) -> Bool {
        return cache[id] != nil
    }

    /// Get the current number of cached threads.
    public var count: Int {
        return cache.count
    }

    /// Get the cache hit rate as a percentage.
    public var hitRate: Double {
        let total = hitCount + missCount
        guard total > 0 else { return 0.0 }
        return Double(hitCount) / Double(total) * 100.0
    }

    /// Reset cache statistics.
    public func resetStatistics() {
        hitCount = 0
        missCount = 0
    }

    // MARK: - Private Helpers

    /// Update the access order for an entry (move to end).
    private func updateAccessOrder(_ id: String) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    /// Evict the least recently used entry.
    private func evictLRU() {
        guard let lruId = accessOrder.first else { return }
        cache.removeValue(forKey: lruId)
        accessOrder.removeFirst()
    }
}

// MARK: - ThreadCache Statistics

extension ThreadCache {

    /// A snapshot of cache statistics for monitoring.
    public struct Statistics: Sendable {
        public let size: Int
        public let maxSize: Int
        public let hitCount: Int
        public let missCount: Int
        public let hitRate: Double

        public var description: String {
            return "ThreadCache: \(size)/\(maxSize) entries, \(hitCount) hits, \(missCount) misses, \(String(format: "%.1f", hitRate))% hit rate"
        }
    }

    /// Get a snapshot of current cache statistics.
    public func getStatistics() -> Statistics {
        return Statistics(
            size: count,
            maxSize: maxSize,
            hitCount: hitCount,
            missCount: missCount,
            hitRate: hitRate
        )
    }
}
