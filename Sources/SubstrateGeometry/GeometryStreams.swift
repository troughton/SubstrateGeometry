import Foundation
import SubstrateMath
import MeshOptimizer

/// GeometryStreams represents raw geometry data.
/// It includes a few utility functions to process geometry and generate missing attributes.
public struct GeometryStreams: Equatable, Codable, Sendable {
    public struct StreamType: Hashable, Codable, Sendable {
        public let rawValue: UInt8
        
        @inlinable
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        @inlinable
        public init(customWithIndex index: Int) {
            precondition(index < 32, "Only 32 custom streams are supported.")
            self.rawValue = UInt8(index + 32)
        }
        
        public static var positions: StreamType { return .init(rawValue: 0) }
        public static var normals: StreamType { return .init(rawValue: 1) }
        public static var tangents: StreamType { return .init(rawValue: 2) }
        public static var bitangents: StreamType { return .init(rawValue: 3) }
        
        public static func texCoords(index: Int) -> StreamType {
            precondition((0..<8).contains(index))
            return .init(rawValue: 4 + UInt8(index))
        }
        
        public static func vertexColors(index: Int) -> StreamType {
            precondition((0..<8).contains(index))
            return .init(rawValue: 12 + UInt8(index))
        }
        
        public static var lightmapCharts: StreamType {
            return .init(rawValue: 21)
        }
    }
    
    public struct StreamMask: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: UInt64
        
        @inlinable
        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }
        
        @inlinable
        public init(stream: StreamType) {
            precondition(stream.rawValue < UInt64.bitWidth)
            self.init(rawValue: 1 << UInt64(stream.rawValue))
        }
        
        public static var positions: StreamMask { return .init(stream: .positions) }
        public static var normals: StreamMask { return .init(stream: .normals) }
        public static var tangents: StreamMask { return .init(stream: .tangents) }
        public static var bitangents: StreamMask { return .init(stream: .bitangents) }
        
        public static func texCoords(index: Int) -> StreamMask { return .init(stream: .texCoords(index: index)) }
        public static func vertexColors(index: Int) -> StreamMask { return .init(stream: .vertexColors(index: index)) }
        
        public static var lightmapCharts: StreamMask { return .init(stream: .lightmapCharts) }
        
        public static var all: StreamMask { return .init(rawValue: ~0) }
    }
    
    public struct Stream: Equatable, Codable, Sendable {
        public var data: Data
        public let size: Int
        public let stride: Int
        
        public init(data: Data, size: Int, stride: Int) {
            precondition(data.count % stride == 0)
            self.data = data
            self.size = size
            self.stride = stride
        }
        
        public init(count: Int, size: Int, stride: Int) {
            self.data = Data()
            self.data.resetBytes(in: 0..<(count * stride))
            self.size = size
            self.stride = stride
        }
        
        public var count: Int {
            get {
                return self.data.count / self.stride
            }
            set {
                let newByteCount = newValue * self.stride
                if newByteCount == self.data.count { return }
                if newByteCount > self.data.count {
                    self.data.resetBytes(in: self.data.count..<newByteCount)
                } else {
                    self.data.removeSubrange(newByteCount..<self.data.count)
                }
            }
        }
        
        @inlinable
        public subscript<T>(index: Int, as type: T.Type = T.self) -> T {
            get {
                return self.data.withUnsafeBytes { $0.load(fromByteOffset: index * self.stride, as: type) }
            }
            set {
                self.data.withUnsafeMutableBytes { $0.storeBytes(of: newValue, toByteOffset: index * self.stride, as: type) }
            }
        }
        
        @inlinable
        public subscript<T>(line: IndexStream.Line, as type: T.Type) -> SubstrateMath.Line<T> {
            get {
                return Line(self[Int(line.v0)], self[Int(line.v1)])
            }
            set {
                self[Int(line.v0)] = newValue.v0
                self[Int(line.v1)] = newValue.v1
            }
        }
        
        @inlinable
        public subscript<T>(triangle: IndexStream.Triangle, as type: T.Type) -> SubstrateMath.Triangle<T> {
            get {
                return Triangle(self[Int(triangle.v0)], self[Int(triangle.v1)], self[Int(triangle.v2)])
            }
            set {
                self[Int(triangle.v0)] = newValue.v0
                self[Int(triangle.v1)] = newValue.v1
                self[Int(triangle.v2)] = newValue.v2
            }
        }
        
        public func withContents<T, R>(as type: T.Type, perform: (UnsafeBufferPointer<T>) throws -> R) rethrows -> R {
            precondition(self.stride % MemoryLayout<T>.stride == 0 && MemoryLayout<T>.stride <= self.stride, "Type \(T.self) has stride \(MemoryLayout<T>.stride), which does not match the stream's stride of \(self.stride)")
            return try self.data.withUnsafeBytes { buffer in
                try perform(buffer.bindMemory(to: type))
            }
        }
        
        public mutating func withMutableContents<T, R>(as type: T.Type, perform: (UnsafeMutableBufferPointer<T>) throws -> R) rethrows -> R {
            precondition(self.stride % MemoryLayout<T>.stride == 0 && MemoryLayout<T>.stride <= self.stride, "Type \(T.self) has stride \(MemoryLayout<T>.stride), which does not match the stream's stride of \(self.stride)")
            return try self.data.withUnsafeMutableBytes { buffer in
                try perform(buffer.bindMemory(to: type))
            }
        }
        
        public func withUnsafeBytes<R>(perform: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
            return try self.data.withUnsafeBytes { buffer in
                try perform(buffer)
            }
        }
        
        public mutating func withUnsafeMutableBytes<R>(perform: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
            return try self.data.withUnsafeMutableBytes { buffer in
                try perform(buffer)
            }
        }
    }
    
    public struct VertexBone: Hashable, Codable, Sendable {
        public var boneIndex: UInt32
        public var weight: Float
        
        public init(boneIndex: UInt32, weight: Float) {
            self.boneIndex = boneIndex
            self.weight = weight
        }
    }
    
    public enum PrimitiveType : UInt8, Hashable, Codable, Sendable {
        case point
        case line
        case lineLoop
        case lineStrip
        case triangle
        case triangleStrip
        case triangleFan
    }
    
    public struct IndexStream: Hashable, Codable, Sendable {
        public typealias Line = SubstrateMath.Line<UInt32>
        public typealias Triangle = SubstrateMath.Triangle<UInt32>
        
        public struct LineCollection: RandomAccessCollection {
            var stream: IndexStream
            
            init(stream: IndexStream) {
                self.stream = stream
            }
            
            public var startIndex: Int { 0 }
            
            public var endIndex: Int {
                switch self.stream.primitiveType {
                case .line:
                    return self.stream.indices.count / 2
                case .lineLoop:
                    return self.stream.indices.count
                case .lineStrip:
                    return self.stream.indices.count - 1
                default:
                    return 0
                }
            }
            
            public func index(after i: Int) -> Int {
                return i + 1
            }
            
            public subscript(primitiveIndex: Int) -> Line {
                get {
                    switch self.stream.primitiveType {
                    case .line:
                        let i0 = self.stream.indices[2 * primitiveIndex]
                        let i1 = self.stream.indices[2 * primitiveIndex + 1]
                        return Line(i0, i1)
                    case .lineLoop:
                        let i0 = self.stream.indices[primitiveIndex]
                        let i1 = self.stream.indices[(primitiveIndex + 1) % self.stream.indices.count]
                        return Line(i0, i1)
                    case .lineStrip:
                        let i0 = self.stream.indices[primitiveIndex]
                        let i1 = self.stream.indices[primitiveIndex + 1]
                        return Line(i0, i1)
                    default:
                        preconditionFailure("Index \(primitiveIndex) is out of bounds.")
                    }
                }
                set {
                    switch self.stream.primitiveType {
                    case .line:
                        self.stream.indices[2 * primitiveIndex] = UInt32(newValue.v0)
                        self.stream.indices[2 * primitiveIndex + 1] = UInt32(newValue.v1)
                    case .lineLoop:
                        self.stream.indices[primitiveIndex] = UInt32(newValue.v0)
                        self.stream.indices[(primitiveIndex + 1) % self.stream.indices.count] = UInt32(newValue.v1)
                    case .lineStrip:
                        self.stream.indices[primitiveIndex] = UInt32(newValue.v0)
                        self.stream.indices[primitiveIndex + 1] = UInt32(newValue.v1)
                    default:
                        preconditionFailure("Index \(primitiveIndex) is out of bounds.")
                    }
                }
            }
        }
        
        public struct TriangleCollection: RandomAccessCollection {
            var stream: IndexStream
            
            init(stream: IndexStream) {
                self.stream = stream
            }
            
            public var startIndex: Int { 0 }
            
            public var endIndex: Int {
                switch self.stream.primitiveType {
                case .triangle:
                    return self.stream.indices.count / 3
                case .triangleFan:
                    return self.stream.indices.count - 2
                case .triangleStrip:
                    return self.stream.indices.count - 2
                default:
                    return 0
                }
            }
            
            public func index(after i: Int) -> Int {
                return i + 1
            }
            
            public subscript(primitiveIndex: Int) -> Triangle {
                get {
                    switch self.stream.primitiveType {
                    case .triangle:
                        let i0 = self.stream.indices[3 * primitiveIndex]
                        let i1 = self.stream.indices[3 * primitiveIndex + 1]
                        let i2 = self.stream.indices[3 * primitiveIndex + 2]
                        return Triangle(i0, i1, i2)
                    case .triangleFan:
                        let i0 = self.stream.indices[0]
                        let i1 = self.stream.indices[primitiveIndex + 1]
                        let i2 = self.stream.indices[primitiveIndex + 2]
                        return Triangle(i0, i1, i2)
                    case .triangleStrip:
                        let isFlipped = primitiveIndex % 2 != 0
                        let i0 = self.stream.indices[primitiveIndex]
                        let i1 = self.stream.indices[primitiveIndex + (isFlipped ? 2 : 1)]
                        let i2 = self.stream.indices[primitiveIndex + (isFlipped ? 1 : 2)]
                        return Triangle(i0, i1, i2)
                    default:
                        preconditionFailure("Index \(primitiveIndex) is out of bounds.")
                    }
                }
                set {
                    switch self.stream.primitiveType {
                    case .triangle:
                        self.stream.indices[3 * primitiveIndex] = UInt32(newValue.v0)
                        self.stream.indices[3 * primitiveIndex + 1] = UInt32(newValue.v1)
                        self.stream.indices[3 * primitiveIndex + 2] = UInt32(newValue.v2)
                    case .triangleFan:
                        self.stream.indices[0] = UInt32(newValue.v0)
                        self.stream.indices[primitiveIndex + 1] = UInt32(newValue.v1)
                        self.stream.indices[primitiveIndex + 2] = UInt32(newValue.v2)
                    case .triangleStrip:
                        let isFlipped = primitiveIndex % 2 != 0
                        self.stream.indices[primitiveIndex] = UInt32(newValue.v0)
                        self.stream.indices[primitiveIndex + (isFlipped ? 2 : 1)] = UInt32(newValue.v1)
                        self.stream.indices[primitiveIndex + (isFlipped ? 1 : 2)] = UInt32(newValue.v2)
                    default:
                        preconditionFailure("Index \(primitiveIndex) is out of bounds.")
                    }
                }
            }
        }
        
        public var primitiveType: PrimitiveType
        public var indices: [UInt32]
        
        public var lineIndices: LineCollection {
            _read {
                yield LineCollection(stream: self)
            }
            _modify {
                var collection = LineCollection(stream: self)
                self.indices = []
                defer { self = collection.stream }
                yield &collection
            }
        }
        
        public var triangleIndices: TriangleCollection {
            _read {
                yield TriangleCollection(stream: self)
            }
            _modify {
                var collection = TriangleCollection(stream: self)
                self.indices = []
                defer { self = collection.stream }
                yield &collection
            }
        }
    }
    
    public struct LineIndicesCollection: BidirectionalCollection {
        public struct Index: Hashable, Comparable, Sendable {
            public var indexStream: Int
            public var primitiveIndex: Int
            
            public static func <(lhs: Index, rhs: Index) -> Bool {
                if lhs.indexStream < rhs.indexStream {
                    return true
                }
                if lhs.indexStream == rhs.indexStream {
                    return lhs.primitiveIndex < rhs.primitiveIndex
                }
                return false
            }
        }
        
        var geometry: GeometryStreams
        
        init(geometry: GeometryStreams) {
            self.geometry = geometry
        }
        
        public var startIndex: Index { Index(indexStream: 0, primitiveIndex: 0) }
        
        public var endIndex: Index { Index(indexStream: self.geometry.indexStreams.endIndex, primitiveIndex: 0) }
        
        public func index(before i: Index) -> Index {
            var result = i
            result.primitiveIndex -= 1
            if result.primitiveIndex < 0 {
                result.indexStream -= 1
                result.primitiveIndex += self.geometry.indexStreams[result.indexStream].lineIndices.count
            }
            return result
        }
        
        public func index(after i: Index) -> Index {
            var result = i
            result.primitiveIndex += 1
            if result.primitiveIndex >= self.geometry.indexStreams[result.indexStream].lineIndices.endIndex {
                result.primitiveIndex = 0
                result.indexStream += 1
            }
            return result
        }
        
        public func index(_ i: Index, offsetBy distance: Int) -> Index {
            var remaining = distance + i.primitiveIndex
            var result = i
            result.primitiveIndex = 0
            
            while result.indexStream < self.geometry.indexStreams.count &&
                   remaining >= self.geometry.indexStreams[result.indexStream].lineIndices.count {
                remaining -= self.geometry.indexStreams[result.indexStream].lineIndices.count
                result.indexStream += 1
            }
            result.primitiveIndex = remaining
            return result
        }
        
        public subscript(i: Index) -> Line<UInt32> {
            get {
                return self.geometry.indexStreams[i.indexStream].lineIndices[i.primitiveIndex]
            }
            set {
                self.geometry.indexStreams[i.indexStream].lineIndices[i.primitiveIndex] = newValue
            }
        }
        
        public subscript(i: Int) -> Line<UInt32> {
            get {
                return self[self.index(self.startIndex, offsetBy: i)]
            }
            set {
                self[self.index(self.startIndex, offsetBy: i)] = newValue
            }
        }
    }
    
    public struct TriangleIndicesCollection: BidirectionalCollection {
        public struct Index: Hashable, Comparable, Sendable {
            public var indexStream: Int
            public var primitiveIndex: Int
            
            public static func <(lhs: Index, rhs: Index) -> Bool {
                if lhs.indexStream < rhs.indexStream {
                    return true
                }
                if lhs.indexStream == rhs.indexStream {
                    return lhs.primitiveIndex < rhs.primitiveIndex
                }
                return false
            }
        }
        
        var geometry: GeometryStreams
        
        init(geometry: GeometryStreams) {
            self.geometry = geometry
        }
        
        public var startIndex: Index { Index(indexStream: 0, primitiveIndex: 0) }
        
        public var endIndex: Index { Index(indexStream: self.geometry.indexStreams.endIndex, primitiveIndex: 0) }
        
        public func index(before i: Index) -> Index {
            var result = i
            result.primitiveIndex -= 1
            if result.primitiveIndex < 0 {
                result.indexStream -= 1
                result.primitiveIndex += self.geometry.indexStreams[result.indexStream].triangleIndices.count
            }
            return result
        }
        
        public func index(after i: Index) -> Index {
            var result = i
            result.primitiveIndex += 1
            if result.primitiveIndex >= self.geometry.indexStreams[result.indexStream].triangleIndices.endIndex {
                result.primitiveIndex = 0
                result.indexStream += 1
            }
            return result
        }
        
        public func index(_ i: Index, offsetBy distance: Int) -> Index {
            var remaining = distance + i.primitiveIndex
            var result = i
            result.primitiveIndex = 0
            
            while result.indexStream < self.geometry.indexStreams.count &&
                   remaining >= self.geometry.indexStreams[result.indexStream].triangleIndices.count {
                remaining -= self.geometry.indexStreams[result.indexStream].triangleIndices.count
                result.indexStream += 1
            }
            result.primitiveIndex = remaining
            return result
        }
        
        public subscript(i: Index) -> Triangle<UInt32> {
            get {
                return self.geometry.indexStreams[i.indexStream].triangleIndices[i.primitiveIndex]
            }
            set {
                self.geometry.indexStreams[i.indexStream].triangleIndices[i.primitiveIndex] = newValue
            }
        }
        
        public subscript(i: Int) -> Triangle<UInt32> {
            get {
                return self[self.index(self.startIndex, offsetBy: i)]
            }
            set {
                self[self.index(self.startIndex, offsetBy: i)] = newValue
            }
        }
    }
    
    public var vertexCount: Int {
        didSet {
            if self.vertexCount == oldValue { return }
            
            for i in self.streams.indices {
                self.streams[i]?.count = vertexCount
            }
            if self.boneIndicesAndWeights != nil {
                if vertexCount > self.boneIndicesAndWeights!.count {
                    self.boneIndicesAndWeights!.append(contentsOf: repeatElement([], count: vertexCount - self.boneIndicesAndWeights!.count))
                } else {
                    self.boneIndicesAndWeights!.removeSubrange(vertexCount..<self.boneIndicesAndWeights!.count)
                }
            }
        }
    }
    
    public var streams = [Stream?](repeating: nil, count: StreamMask.RawValue.bitWidth)
    
    public var indexStreams = [IndexStream]()
    
    public var boneIndicesAndWeights: [[VertexBone]]?
    
    public init(vertexCount: Int) {
        self.vertexCount = vertexCount
    }
    
    @inlinable
    public subscript(streamType: StreamType) -> Stream? {
        _read {
            yield self.streams[Int(streamType.rawValue)]
        }
        _modify {
            yield &self.streams[Int(streamType.rawValue)]
        }
    }
    
    @inlinable
    public var positions: Stream {
        _read {
            yield self[.positions]!
        }
        _modify {
            yield &self[.positions]!
        }
    }
    
    @inlinable
    public var normals: Stream? {
        _read {
            yield self[.normals]
        }
        _modify {
            yield &self[.normals]
        }
    }
    
    @inlinable
    public var tangents: Stream? {
        _read {
            yield self[.tangents]
        }
        _modify {
            yield &self[.tangents]
        }
    }
    
    public var pointIndices: some Sequence<Int> {
        return self.indexStreams.lazy.filter { $0.primitiveType == .point }.flatMap { $0.indices.lazy.map { Int($0) } }
    }
    
    public var lineIndices: LineIndicesCollection {
        _read {
            yield LineIndicesCollection(geometry: self)
        }
        _modify {
            var collection = LineIndicesCollection(geometry: self)
            self = .init(vertexCount: 0)
            defer { self = collection.geometry }
            yield &collection
        }
    }
    
    public var triangleIndices: TriangleIndicesCollection {
        _read {
            yield TriangleIndicesCollection(geometry: self)
        }
        _modify {
            var collection = TriangleIndicesCollection(geometry: self)
            self = .init(vertexCount: 0)
            defer { self = collection.geometry }
            yield &collection
        }
    }
    
    private var _pointIndicesArray: [UInt32] {
        var result = [UInt32]()
        for stream in self.indexStreams {
            switch stream.primitiveType {
            case .point:
                if result.isEmpty {
                    result = stream.indices
                } else {
                    result.append(contentsOf: stream.indices)
                }
            default:
                continue
            }
        }
        return result
    }
    
    private var _triangleIndicesArray: [UInt32] {
        var result = [UInt32]()
        for stream in self.indexStreams {
            switch stream.primitiveType {
            case .triangle:
                if result.isEmpty {
                    result = stream.indices
                } else {
                    result.append(contentsOf: stream.indices)
                }
            default:
                result.reserveCapacity(result.capacity + 3 * stream.triangleIndices.count)
                for triangle in stream.triangleIndices {
                    result.append(triangle.v0)
                    result.append(triangle.v1)
                    result.append(triangle.v2)
                }
            }
        }
        return result
    }
    
    public var pointIndicesArray: [UInt32] {
        get {
            return self._pointIndicesArray
        }
        _modify {
            var pointIndicesArray = self._pointIndicesArray
            self.indexStreams.removeAll(where: { $0.primitiveType == .point })
            defer { self.indexStreams.append(IndexStream(primitiveType: .point, indices: pointIndicesArray)) }
            yield &pointIndicesArray
        }
        set {
            self.indexStreams.removeAll(where: { $0.primitiveType == .point })
            self.indexStreams.append(IndexStream(primitiveType: .point, indices: newValue))
        }
    }
    
    public var triangleIndicesArray: [UInt32] {
        get {
            return self._triangleIndicesArray
        }
        _modify {
            var triangleIndicesArray = self._triangleIndicesArray
            self.indexStreams.removeAll(where: { !$0.triangleIndices.isEmpty })
            defer { self.indexStreams.append(IndexStream(primitiveType: .triangle, indices: triangleIndicesArray)) }
            yield &triangleIndicesArray
        }
        set {
            self.indexStreams.removeAll(where: { !$0.triangleIndices.isEmpty })
            self.indexStreams.append(IndexStream(primitiveType: .triangle, indices: newValue))
        }
    }
    
    public var boundingBox: AxisAlignedBoundingBox<Float> {
        var box = AxisAlignedBoundingBox<Float>.baseBox
        for i in 0..<self[.positions]!.count {
            let position = SIMD3(self[.positions]![i, as: PackedVector3<Float>.self])
            box.expandToInclude(point: position)
        }
        return box
    }
    
    public mutating func makeStream(type: StreamType, sizePerVertex: Int, stridePerVertex: Int) {
        self[type] = .init(count: self.vertexCount, size: sizePerVertex, stride: stridePerVertex)
    }
    
    /// Transforms all vertex positions by the given transform matrix.
    public mutating func transformPositions(by transform: AffineMatrix<Float>) {
        if self[.positions] != nil {
            for i in 0..<self[.positions]!.count {
                self[.positions]![i] = PackedVector3((transform * SIMD4(self[.positions]![i, as: PackedVector3<Float>.self], 1)).xyz)
            }
        }
    }
    
    /// Transforms all vertex positions, normals, and tangents by the given transform matrix.
    /// The inverse transpose transform is applied to the normals in order to preserve correct scaling.
    public mutating func transformVertices(by transform: AffineMatrix<Float>) {
        self.transformPositions(by: transform)
        
        if self[.normals] != nil {
            let normalTransform = Matrix3x3f(transform).inverse.transpose
            for i in 0..<self[.normals]!.count {
                self[.normals]![i] = PackedVector3(normalTransform * SIMD3(self[.normals]![i, as: PackedVector3<Float>.self]))
            }
        }
        
        if self[.tangents] != nil {
            for i in 0..<self[.tangents]!.count {
                self[.tangents]![i] = PackedVector3((transform * SIMD4(self[.tangents]![i, as: PackedVector3<Float>.self], 1)).xyz)
            }
        }
    }
    
    /// Conforms the triangle winding such that the face normals match a counter-clockwise winding order.
    public mutating func makeTrianglesCounterClockwiseWinding() {
        precondition(self[.positions] != nil && self[.normals] != nil, "Both positions and normals must be present.")
        
        for i in self.triangleIndices.indices {
            var triangle = self.triangleIndices[i]
            let v0 = SIMD3(self.positions[Int(triangle.v0), as: PackedVector3<Float>.self])
            let v1 = SIMD3(self.positions[Int(triangle.v1), as: PackedVector3<Float>.self])
            let v2 = SIMD3(self.positions[Int(triangle.v2), as: PackedVector3<Float>.self])
            
            let crossProduct = cross(v2 - v0, v1 - v0)
            let normals = self.normals![triangle, as: PackedVector3<Float>.self]
            let averageNormal = SIMD3(normals.v0) + SIMD3(normals.v1) + SIMD3(normals.v2)
            if dot(crossProduct, averageNormal) < 0.0 {
                let tmp = triangle.v0
                triangle.v0 = triangle.v2
                triangle.v2 = tmp
                
                self.triangleIndices[i] = triangle
            }
        }
    }
    
    /// Computes vertex normals from the positions and the index buffer.
    public mutating func generateNormals() {
        if self.positions.count == self.triangleIndices.count * 3 {
            self.deduplicateVertices()
        }
        
        self.normals = .init(count: self.positions.count, size: 3 * MemoryLayout<Float>.stride, stride: MemoryLayout<SIMD3<Float>>.stride)
        
        for triangleIndices in self.triangleIndices {
            let triangle = self.positions[triangleIndices, as: PackedVector3<Float>.self]
            let v0 = SIMD3(triangle.v0)
            let v1 = SIMD3(triangle.v1)
            let v2 = SIMD3(triangle.v2)
            
            let crossProduct = cross(v2 - v0, v1 - v0)
            self.normals![Int(triangleIndices.v0), as: SIMD3<Float>.self] += crossProduct
            self.normals![Int(triangleIndices.v1), as: SIMD3<Float>.self] += crossProduct
            self.normals![Int(triangleIndices.v2), as: SIMD3<Float>.self] += crossProduct
        }
        
        for i in 0..<self.normals!.count {
            self.normals![i, as: SIMD3<Float>.self] = normalize(self.normals![i, as: SIMD3<Float>.self])
        }
    }
}

extension GeometryStreams {
    public var isManifold : Bool {
        struct Edge : Hashable {
            var from : UInt32
            var to : UInt32
            
            init(_ a: UInt32, _ b: UInt32) {
                self.from = a
                self.to = b
            }
        }
        
        // For a manifold mesh, each edge may occur at most twice.
        // However, when face winding is in place, each directed edge may occur at most once.
        
        var edges = Set<Edge>()
        
        let faceCount = self.triangleIndices.count
        
        edges.reserveCapacity(2 * faceCount)
        
        for triangle in self.triangleIndices {
            let e0 = Edge(UInt32(truncatingIfNeeded: triangle.v0), UInt32(truncatingIfNeeded: triangle.v1))
            let e1 = Edge(UInt32(truncatingIfNeeded: triangle.v1), UInt32(truncatingIfNeeded: triangle.v2))
            let e2 = Edge(UInt32(truncatingIfNeeded: triangle.v2), UInt32(truncatingIfNeeded: triangle.v0))
            
            if !edges.insert(e0).inserted {
                return false
            }
            
            if !edges.insert(e1).inserted {
                return false
            }
            
            if !edges.insert(e2).inserted {
                return false
            }
        }
        
        return true
    }
}

extension GeometryStreams {
    
    /// For debugging purposes, writes all geometry in the scene out to a Wavefront OBJ file at the specified URL.
    public func writeAsOBJ(to url: URL) throws {
        var outputOBJ = ""
        
        print("# Positions", to: &outputOBJ)
        for i in 0..<self.positions.count {
            let v = self.positions[i, as: PackedVector3<Float>.self]
            print("v \(v.x) \(v.y) \(-v.z)", to: &outputOBJ)
        }
        
        if let normals = self.normals {
            print("# Normals", to: &outputOBJ)
            for i in 0..<normals.count {
                let n = normals[i, as: PackedVector3<Float>.self]
                print("vn \(n.x) \(n.y) \(-n.z)", to: &outputOBJ)
            }
        }
        
        if let texCoords = self[.texCoords(index: 0)] {
            print("# Texture Coordinates", to: &outputOBJ)
            for i in 0..<texCoords.count {
                let uv = texCoords[i, as: (x: Float, y: Float).self]
                print("vt \(uv.x) \(1.0 - uv.y)", to: &outputOBJ)
            }
        }
        
        print("# Geometry", to: &outputOBJ)
        
        for (i, indexStream) in self.indexStreams.enumerated() {
            guard !indexStream.indices.isEmpty else { continue }
            
            if self.indexStreams.count > 1 {
                print("g IndexStream\(i + 1)", to: &outputOBJ)
            }
            switch indexStream.primitiveType {
            case .point:
                break
            case .line:
                for line in indexStream.lineIndices {
                    print("l \(line.v0 + 1) \(line.v1 + 1)", to: &outputOBJ)
                }
            case .lineLoop:
                print("l \(indexStream.indices.lazy.map { String($0 + 1) }.joined(separator: " ")) \(indexStream.indices[0] + 1)")
            case .lineStrip:
                print("l \(indexStream.indices.lazy.map { String($0 + 1) }.joined(separator: " "))")
            case .triangle, .triangleStrip, .triangleFan:
                for triangle in indexStream.triangleIndices {
                    let v0 = triangle.v0 + 1
                    let v1 = triangle.v1 + 1
                    let v2 = triangle.v2 + 1
                    print("f \(v0)/\(v0)/\(v0) \(v1)/\(v1)/\(v1) \(v2)/\(v2)/\(v2)", to: &outputOBJ)
                }
            }
        }
        
        try outputOBJ.write(to: url, atomically: false, encoding: .ascii)
    }
}

extension GeometryStreams {
    public struct SkinningData {
        public var vertexOffsetTable: [UInt32]
        public var boneIndices: [UInt32]
        public var boneWeights: [Float]
    }
    
    public func buildSkinningData() -> SkinningData? {
        guard let boneIndicesAndWeights = self.boneIndicesAndWeights else {
            return nil
        }
        assert(boneIndicesAndWeights.count == self.vertexCount)
        
        var offsetTable = [UInt32](repeating: 0, count: boneIndicesAndWeights.count + 1)
        var offset = 0 as UInt32
        for (i, vertexBones) in boneIndicesAndWeights.enumerated() {
            offsetTable[i] = offset
            offset += UInt32(vertexBones.count)
        }
        
        let count = Int(offset)
        offsetTable[boneIndicesAndWeights.count] = offset
        
        var boneIndices = [UInt32](repeating: 0, count: count)
        var boneWeights = [Float](repeating: 0.0, count: count)
     
        for (i, vertexBones) in boneIndicesAndWeights.enumerated() {
            let offset = Int(offsetTable[i])
            
            for (j, bone) in vertexBones.enumerated() {
                boneIndices[offset + j] = bone.boneIndex
                boneWeights[offset + j] = bone.weight
            }
        }
        
        return SkinningData(vertexOffsetTable: offsetTable, boneIndices: boneIndices, boneWeights: boneWeights)
    }
}
