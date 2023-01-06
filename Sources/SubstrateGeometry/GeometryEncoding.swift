#if canImport(MeshOptimizer)
import MeshOptimizer

public enum GeometryEncoding {
    public enum IndexEncodingVersion: Int {
        case v0 = 0
        case v1 = 1
    }
    
    public struct DecodingError: Error {
        public let rawValue: Int32
    }
    
    // MARK: Index Buffer Encoding
    
    public static func capacityBoundForEncodingIndexBuffer(indexCount: Int, vertexCount: Int) -> Int {
        return meshopt_encodeIndexBufferBound(indexCount, vertexCount)
    }
    
    public static func encodeIndexBuffer(_ indexBuffer: UnsafeBufferPointer<UInt32>, into outputBuffer: UnsafeMutableRawBufferPointer, version: IndexEncodingVersion) -> Int {
        return meshopt_encodeIndexBuffer(outputBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self), outputBuffer.count, indexBuffer.baseAddress, indexBuffer.count, version.rawValue)
    }
    
    public static func encodeIndexBuffer(_ indexBuffer: UnsafeBufferPointer<UInt32>, vertexCount: Int, version: IndexEncodingVersion) -> [UInt8] {
        return [UInt8](unsafeUninitializedCapacity: self.capacityBoundForEncodingIndexBuffer(indexCount: indexBuffer.count, vertexCount: vertexCount)) { buffer, initializedCount in
            initializedCount = self.encodeIndexBuffer(indexBuffer, into: UnsafeMutableRawBufferPointer(buffer), version: version)
        }
    }
    
    public static func encodeIndexBuffer(_ indexBuffer: [UInt32], vertexCount: Int, version: IndexEncodingVersion) -> [UInt8] {
        return indexBuffer.withUnsafeBufferPointer { indexBuffer in
            self.encodeIndexBuffer(indexBuffer, vertexCount: vertexCount, version: version)
        }
    }
    
    // MARK: Index Buffer Decoding
    
    public static func decodeIndexBuffer<U: UnsignedInteger>(_ encodedIndexBuffer: UnsafeRawBufferPointer, into indices: UnsafeMutableBufferPointer<U>) throws {
        let encodedIndexBuffer = encodedIndexBuffer.bindMemory(to: UInt8.self)
        let result = meshopt_decodeIndexBuffer(indices.baseAddress, indices.count, MemoryLayout<U>.stride, encodedIndexBuffer.baseAddress, encodedIndexBuffer.count)
        if result != 0 {
            throw DecodingError(rawValue: result)
        }
    }
    
    public static func decodeIndexBuffer<U: UnsignedInteger>(_ encodedIndexBuffer: [UInt8], into indices: UnsafeMutableBufferPointer<U>) throws {
        try encodedIndexBuffer.withUnsafeBytes {
            try self.decodeIndexBuffer($0, into: indices)
        }
    }
    
    // MARK: Index Sequence Encoding
    
    public static func capacityBoundForEncodingIndexSequence(indexCount: Int, vertexCount: Int) -> Int {
        return meshopt_encodeIndexSequenceBound(indexCount, vertexCount)
    }
    
    public static func encodeIndexSequence(_ indexBuffer: UnsafeBufferPointer<UInt32>, into outputBuffer: UnsafeMutableRawBufferPointer, version: IndexEncodingVersion) -> Int {
        return meshopt_encodeIndexSequence(outputBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self), outputBuffer.count, indexBuffer.baseAddress, indexBuffer.count, version.rawValue)
    }
    
    public static func encodeIndexSequence(_ indexBuffer: UnsafeBufferPointer<UInt32>, vertexCount: Int, version: IndexEncodingVersion) -> [UInt8] {
        return [UInt8](unsafeUninitializedCapacity: self.capacityBoundForEncodingIndexSequence(indexCount: indexBuffer.count, vertexCount: vertexCount)) { buffer, initializedCount in
            initializedCount = self.encodeIndexSequence(indexBuffer, into: UnsafeMutableRawBufferPointer(buffer), version: version)
        }
    }
    
    public static func encodeIndexSequence(_ indexBuffer: [UInt32], vertexCount: Int, version: IndexEncodingVersion) -> [UInt8] {
        return indexBuffer.withUnsafeBufferPointer { indexBuffer in
            self.encodeIndexSequence(indexBuffer, vertexCount: vertexCount, version: version)
        }
    }
    
    // MARK: Index Sequence Decoding
    
    public static func decodeIndexSequence<U: UnsignedInteger>(_ encodedIndexBuffer: UnsafeRawBufferPointer, into indices: UnsafeMutableBufferPointer<U>) throws {
        let encodedIndexBuffer = encodedIndexBuffer.bindMemory(to: UInt8.self)
        let result = meshopt_decodeIndexSequence(indices.baseAddress, indices.count, MemoryLayout<U>.stride, encodedIndexBuffer.baseAddress, encodedIndexBuffer.count)
        if result != 0 {
            throw DecodingError(rawValue: result)
        }
    }
    
    public static func decodeIndexSequence<U: UnsignedInteger>(_ encodedIndexBuffer: [UInt8], into indices: UnsafeMutableBufferPointer<U>) throws {
        try encodedIndexBuffer.withUnsafeBytes {
            try self.decodeIndexSequence($0, into: indices)
        }
    }
    
    // MARK: Vertex Buffer Encoding
    
    public static func capacityBoundForEncodingVertexBuffer<V>(vertexType: V.Type, vertexCount: Int) -> Int {
        return meshopt_encodeVertexBufferBound(vertexCount, MemoryLayout<V>.stride)
    }
    
    public static func encodeVertexBuffer<V>(_ vertexBuffer: UnsafeBufferPointer<V>, into outputBuffer: UnsafeMutableRawBufferPointer) -> Int {
        return meshopt_encodeVertexBuffer(outputBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self), outputBuffer.count, vertexBuffer.baseAddress, vertexBuffer.count, MemoryLayout<V>.stride)
    }
    
    public static func encodeVertexBuffer<V>(_ vertexBuffer: UnsafeBufferPointer<V>) -> [UInt8] {
        return [UInt8](unsafeUninitializedCapacity: self.capacityBoundForEncodingVertexBuffer(vertexType: V.self, vertexCount: vertexBuffer.count)) { buffer, initializedCount in
            initializedCount = self.encodeVertexBuffer(vertexBuffer, into: UnsafeMutableRawBufferPointer(buffer))
        }
    }
    
    public static func encodeVertexBuffer<V>(_ vertexBuffer: [V]) -> [UInt8] {
        return vertexBuffer.withUnsafeBufferPointer { vertexBuffer in
            self.encodeVertexBuffer(vertexBuffer)
        }
    }
    
    // MARK: Vertex Buffer Decoding
    
    public static func decodeVertexBuffer<V>(_ encodedVertexBuffer: UnsafeRawBufferPointer, into vertices: UnsafeMutableBufferPointer<V>) throws {
        let encodedVertexBuffer = encodedVertexBuffer.bindMemory(to: UInt8.self)
        let result = meshopt_decodeVertexBuffer(vertices.baseAddress, vertices.count, MemoryLayout<V>.stride, encodedVertexBuffer.baseAddress, encodedVertexBuffer.count)
        if result != 0 {
            throw DecodingError(rawValue: result)
        }
    }
    
    public static func decodeVertexBuffer<V>(_ encodedVertexBuffer: [UInt8], into vertices: UnsafeMutableBufferPointer<V>) throws {
        try encodedVertexBuffer.withUnsafeBytes {
            try self.decodeVertexBuffer($0, into: vertices)
        }
    }
}

#endif // canImport(MeshOptimizer)
