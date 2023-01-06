//
//  GeometryStreams+MeshOptimizer.swift
//  
//
//  Created by Thomas Roughton on 7/01/23.
//

#if canImport(MeshOptimizer)
import MeshOptimizer
import SubstrateMath

extension GeometryStreams {
    /**
     * Generate index buffer that can be used for more efficient rendering when only a subset of the vertex attributes is necessary
     * All vertices that are binary equivalent (wrt specified streams) map to the first vertex in the original vertex buffer.
     * This makes it possible to use the index buffer for Z pre-pass or shadowmap rendering, while using the original index buffer for regular rendering.
     * Note that binary equivalence considers all size bytes in each stream, including padding which should be zero-initialized.
     */
    public func generateShadowIndexBuffer(streamMask: StreamMask = .all) -> IndexStream {
        let inputIndices = self.triangleIndicesArray
        let indices = [UInt32](unsafeUninitializedCapacity: inputIndices.count) { buffer, initializedCount in
            self.withMeshOptStreams(mask: streamMask) { streams in
                meshopt_generateShadowIndexBufferMulti(buffer.baseAddress!, inputIndices, inputIndices.count, self.positions.count, streams, streams.count)
            }
            initializedCount = inputIndices.count
        }
        return IndexStream(primitiveType: .triangle, indices: indices)
    }
    
    /**
     * Generate index buffer that can be used as a geometry shader input with triangle adjacency topology
     * Each triangle is converted into a 6-vertex patch with the following layout:
     * - 0, 2, 4: original triangle vertices
     * - 1, 3, 5: vertices adjacent to edges 02, 24 and 40
     * The resulting patch can be rendered with geometry shaders using e.g. VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST_WITH_ADJACENCY.
     * This can be used to implement algorithms like silhouette detection/expansion and other forms of GS-driven rendering.
     *
     * destination must contain enough space for the resulting index buffer (index_count*2 elements)
     * vertex_positions should have float3 position in the first 12 bytes of each vertex - similar to glVertexPointer
     */
    public func generateAdjacencyIndexBuffer(streamMask: StreamMask = .all) -> IndexStream {
        let inputIndices = self.triangleIndicesArray
        let indices = [UInt32](unsafeUninitializedCapacity: inputIndices.count * 2) { buffer, initializedCount in
            self.positions.withContents(as: Float.self) { positions in
                meshopt_generateAdjacencyIndexBuffer(buffer.baseAddress!, inputIndices, inputIndices.count, positions.baseAddress, self.positions.count, self.positions.stride)
            }
            initializedCount = inputIndices.count * 2
        }
        return IndexStream(primitiveType: .triangle, indices: indices)
    }
    
    /**
     * Generate index buffer that can be used for PN-AEN tessellation with crack-free displacement
     * Each triangle is converted into a 12-vertex patch with the following layout:
     * - 0, 1, 2: original triangle vertices
     * - 3, 4: opposing edge for edge 0, 1
     * - 5, 6: opposing edge for edge 1, 2
     * - 7, 8: opposing edge for edge 2, 0
     * - 9, 10, 11: dominant vertices for corners 0, 1, 2
     * The resulting patch can be rendered with hardware tessellation using PN-AEN and displacement mapping.
     * See "Tessellation on Any Budget" (John McDonald, GDC 2011) for implementation details.
     *
     * destination must contain enough space for the resulting index buffer (index_count*4 elements)
     * vertex_positions should have float3 position in the first 12 bytes of each vertex - similar to glVertexPointer
     */
    public func generateTesselationIndexBuffer(streamMask: StreamMask = .all) -> IndexStream {
        let inputIndices = self.triangleIndicesArray
        let indices = [UInt32](unsafeUninitializedCapacity: inputIndices.count * 4) { buffer, initializedCount in
            self.positions.withContents(as: Float.self) { positions in
                meshopt_generateAdjacencyIndexBuffer(buffer.baseAddress!, inputIndices, inputIndices.count, positions.baseAddress, self.positions.count, self.positions.stride)
            }
            initializedCount = inputIndices.count * 4
        }
        return IndexStream(primitiveType: .triangle, indices: indices)
    }
    
    /// Generates a new set of vertex buffers and index buffer by ensuring each vertex is referenced exactly once.
    /// This means that vertices may be duplicated in the resulting vertex buffers.
    public mutating func uniqueIndexBufferVertices() {
        let triangleIndices = self.triangleIndicesArray
        for streamIndex in self.streams.indices where self.streams[streamIndex] != nil {
            let stride = self.streams[streamIndex]!.stride
            var newStream = Stream(count: triangleIndices.count, size: self.streams[streamIndex]!.size, stride: stride)
            newStream.withUnsafeMutableBytes { newStreamBytes in
                self.streams[streamIndex]!.withUnsafeBytes { oldStreamBytes in
                    for i in 0..<triangleIndices.count {
                        let dest = newStreamBytes.baseAddress! + i * stride
                        dest.copyMemory(from: oldStreamBytes.baseAddress! + Int(triangleIndices[i]) * stride, byteCount: stride)
                    }
                }
            }
            self.streams[streamIndex] = newStream
        }
        
        self.triangleIndicesArray = Array(0..<UInt32(triangleIndices.count))
    }
    
    mutating func remapBuffers(vertexRemap: [UInt32]) {
        let vertexCount = self.vertexCount
        for streamIndex in self.streams.indices where self.streams[streamIndex] != nil {
            let stride = self.streams[streamIndex]!.stride
            var newStream = Stream(count: vertexRemap.count, size: self.streams[streamIndex]!.size, stride: stride)
            newStream.withUnsafeMutableBytes { newStreamBytes in
                self.streams[streamIndex]!.withUnsafeBytes { oldStreamBytes in
                    meshopt_remapVertexBuffer(newStreamBytes.baseAddress!, oldStreamBytes.baseAddress!, vertexCount, stride, vertexRemap)
                }
            }
            self.streams[streamIndex] = newStream
        }
        
        if let sourceBoneIndicesAndWeights = self.boneIndicesAndWeights {
            self.boneIndicesAndWeights = .init(unsafeUninitializedCapacity: vertexRemap.count, initializingWith: { outBuffer, initializedCount in
                initializedCount = vertexRemap.count
                
                for i in 0..<vertexRemap.count {
                    if vertexRemap[i] != ~0 {
                        assert(vertexRemap[i] < vertexCount)
                        outBuffer.baseAddress!.advanced(by: Int(vertexRemap[i])).initialize(to: sourceBoneIndicesAndWeights[i])
                    }
                }
            })
        }
        
        self.vertexCount = vertexRemap.count
        
        for i in self.indexStreams.indices {
            self.indexStreams[i].indices = [UInt32](unsafeUninitializedCapacity: self.indexStreams[i].indices.count, initializingWith: { buffer, filledCount in
                meshopt_remapIndexBuffer(buffer.baseAddress, self.indexStreams[i].indices, self.indexStreams[i].indices.count, vertexRemap)
                filledCount = self.indexStreams[i].indices.count
            })
        }
    }
    
    private func withMeshOptStreams<R>(mask: StreamMask = .all, perform: ([meshopt_Stream]) throws -> R) rethrows -> R {
        func addingStreams<R>(to streams: inout [meshopt_Stream], currentIndex: Int = 0, perform: ([meshopt_Stream]) throws -> R) rethrows -> R {
            guard currentIndex < self.streams.count else {
                return try perform(streams)
            }
            
            if mask.contains(.init(rawValue: 1 << currentIndex)), self.streams[currentIndex] != nil {
                return try self.streams[currentIndex]!.withUnsafeBytes {
                    streams.append(meshopt_Stream(data: $0.baseAddress, size: self.streams[currentIndex]!.size, stride: self.streams[currentIndex]!.stride))
                    return try addingStreams(to: &streams, currentIndex: currentIndex + 1, perform: perform)
                }
            } else {
                return try addingStreams(to: &streams, currentIndex: currentIndex + 1, perform: perform)
            }
        }
        
        var streams = [meshopt_Stream]()
        return try addingStreams(to: &streams, perform: perform)
    }
    
    /// Generates a new set of vertex buffers and index buffer by removing duplicate vertices.
    public mutating func deduplicateVertices() {
        let vertexRemap = [UInt32](unsafeUninitializedCapacity: self.positions.count * 3, initializingWith: { buffer, filledCount in
            withMeshOptStreams { streams in
                filledCount = self.triangleIndicesArray.withUnsafeBufferPointer {
                    meshopt_generateVertexRemapMulti(buffer.baseAddress, $0.baseAddress!, $0.count, self.positions.count, streams, streams.count)
                }
            }
        })
        
        self.remapBuffers(vertexRemap: vertexRemap)
    }
    
    public struct SimplifyOptions: OptionSet {
        public let rawValue: UInt32
        
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        /// Do not move vertices that are located on the topological border (vertices on triangle edges that don't have a paired triangle). Useful for simplifying portions of the larger mesh.
        public static var simplifyLockBorder: SimplifyOptions {
            return .init(rawValue: UInt32(meshopt_SimplifyLockBorder))
        }
    }
    
    @discardableResult
    public mutating func simplify(targetIndexCount: Int, targetError: Float, options: SimplifyOptions = []) -> Float {
        var resultError = 0.0 as Float
        
        let triangleIndices = self.triangleIndicesArray
        self.triangleIndicesArray = [UInt32](unsafeUninitializedCapacity: triangleIndices.count, initializingWith: { buffer, filledCount in
            triangleIndices.withUnsafeBufferPointer { indices in
                self.positions.withContents(as: Float.self) { positions in
                    filledCount = meshopt_simplify(buffer.baseAddress, indices.baseAddress, indices.count, positions.baseAddress, self.positions.count, self.positions.stride, targetIndexCount, targetError, options.rawValue, &resultError)
                }
                
            }
        })
        return resultError
    }
    
    @discardableResult
    public mutating func simplifySloppy(targetIndexCount: Int, targetError: Float) -> Float {
        var resultError = 0.0 as Float
        let triangleIndices = self.triangleIndicesArray
        let newIndices = [UInt32](unsafeUninitializedCapacity: triangleIndices.count, initializingWith: { buffer, filledCount in
            triangleIndices.withUnsafeBufferPointer { indices in
                self.positions.withContents(as: Float.self) { positions in
                    filledCount = meshopt_simplifySloppy(buffer.baseAddress, indices.baseAddress, indices.count, positions.baseAddress, self.positions.count, self.positions.stride, targetIndexCount, targetError, &resultError)
                }
                
            }
        })
        self.triangleIndicesArray = newIndices
        return resultError
    }
    
    @discardableResult
    public mutating func simplifyPoints(targetVertexCount: Int) -> Float {
        var resultError = 0.0 as Float
        
        let pointIndices = self.pointIndicesArray
        self.pointIndicesArray = [UInt32](unsafeUninitializedCapacity: pointIndices.count, initializingWith: { buffer, filledCount in
            pointIndices.withUnsafeBufferPointer { indices in
                self.positions.withContents(as: Float.self) { positions in
                    filledCount = meshopt_simplifyPoints(buffer.baseAddress, positions.baseAddress, self.positions.count, self.positions.stride, targetVertexCount)
                }
                
            }
        })
        return resultError
    }
    
    public mutating func optimizeVertexCache() {
        let positionCount = self.positions.count
        self.triangleIndicesArray.withUnsafeMutableBufferPointer { indices in
            meshopt_optimizeVertexCache(indices.baseAddress, indices.baseAddress, indices.count, positionCount)
        }
    }
    
    public mutating func optimizeVertexCacheStrip() {
        let positionCount = self.positions.count
        self.triangleIndicesArray.withUnsafeMutableBufferPointer { indices in
            meshopt_optimizeVertexCacheStrip(indices.baseAddress, indices.baseAddress, indices.count, positionCount)
        }
    }
    
    public mutating func optimizeVertexCacheFIFO(cacheSize: Int) {
        let positionCount = self.positions.count
        self.triangleIndicesArray.withUnsafeMutableBufferPointer { indices in
            meshopt_optimizeVertexCacheFifo(indices.baseAddress, indices.baseAddress, indices.count, positionCount, UInt32(cacheSize))
        }
    }
    
    public mutating func optimizeOverdraw(threshold: Float = 1.05) {
        let positionCount = self.positions.count
        let positionStride = self.positions.stride
        self.positions.withContents(as: Float.self) { positions in
            self.triangleIndicesArray.withUnsafeMutableBufferPointer { indices in
                meshopt_optimizeOverdraw(indices.baseAddress, indices.baseAddress, indices.count, positions.baseAddress, positionCount, positionStride, threshold)
            }
        }
    }
    
    public mutating func optimizeVertexFetch() {
        let vertexRemap = [UInt32](unsafeUninitializedCapacity: self.positions.count, initializingWith: { buffer, filledCount in
            self.triangleIndicesArray.withUnsafeBufferPointer { indices in
                filledCount = meshopt_optimizeVertexFetchRemap(buffer.baseAddress, indices.baseAddress, indices.count, self.positions.count)
            }
        })
        
        self.remapBuffers(vertexRemap: vertexRemap)
    }
}

public struct MeshletGeometry {
    public struct Bounds {
        // bounding sphere, useful for frustum and occlusion culling
        public var sphere: Sphere<Float>
        
        // normal cone, useful for backface culling
        public var coneApex: PackedVector3<Float>
        public var coneAxis: PackedVector3<Float>
        public var coneCutoff: Float /* = cos(angle/2) */
        
        public var coneAxisS8: PackedVector3<Int8>
        public var coneCutoffS8: Int8
        
        init(sphere: Sphere<Float>, coneApex: PackedVector3<Float>, coneAxis: PackedVector3<Float>, coneCutoff: Float, coneAxisS8: PackedVector3<Int8>, coneCutoffS8: Int8) {
            self.sphere = sphere
            self.coneApex = coneApex
            self.coneAxis = coneAxis
            self.coneCutoff = coneCutoff
            self.coneAxisS8 = coneAxisS8
            self.coneCutoffS8 = coneCutoffS8
        }
        
        init(meshoptBounds: meshopt_Bounds) {
            self.init(sphere: .init(centre: SIMD3(meshoptBounds.center.0, meshoptBounds.center.1, meshoptBounds.center.2), radius: meshoptBounds.radius), coneApex: PackedVector3(meshoptBounds.cone_apex.0, meshoptBounds.cone_apex.1, meshoptBounds.cone_apex.2), coneAxis: PackedVector3(meshoptBounds.cone_axis.0, meshoptBounds.cone_axis.1, meshoptBounds.cone_axis.2), coneCutoff: meshoptBounds.cone_cutoff, coneAxisS8: PackedVector3(meshoptBounds.cone_axis_s8.0, meshoptBounds.cone_axis_s8.1, meshoptBounds.cone_axis_s8.2), coneCutoffS8: meshoptBounds.cone_cutoff_s8)
        }
    }
    
    public struct Meshlet {
        // offsets within meshlet_vertices and meshlet_triangles arrays with meshlet data
        public var vertexOffset: UInt32
        public var triangleOffset: UInt32
        
        // number of vertices and triangles used in the meshlet; data is stored in consecutive range defined by offset and count
        public var vertexCount: UInt32
        public var triangleCount: UInt32
    }
    
    let geometry: GeometryStreams
    let meshlets: [Meshlet]
    let vertices: [UInt32]
    let triangles: [UInt8]
    
    public init(geometry: GeometryStreams, meshlets: [Meshlet], vertices: [UInt32], triangles: [UInt8]) {
        self.geometry = geometry
        self.meshlets = meshlets
        self.vertices = vertices
        self.triangles = triangles
    }
    
    public func bounds(for meshlet: Meshlet) -> Bounds {
        let meshoptBounds = geometry.positions.withContents(as: Float.self) { positions in
            self.vertices.withUnsafeBufferPointer { vertices in
                self.triangles.withUnsafeBufferPointer { triangles in
                    meshopt_computeMeshletBounds(vertices.baseAddress?.advanced(by: Int(meshlet.vertexOffset)), triangles.baseAddress?.advanced(by: Int(meshlet.triangleOffset)), Int(meshlet.triangleCount), positions.baseAddress!, geometry.positions.count, geometry.positions.stride)
                }
            }
        }
        return Bounds(sphere: .init(centre: SIMD3(meshoptBounds.center.0, meshoptBounds.center.1, meshoptBounds.center.2), radius: meshoptBounds.radius), coneApex: PackedVector3(meshoptBounds.cone_apex.0, meshoptBounds.cone_apex.1, meshoptBounds.cone_apex.2), coneAxis: PackedVector3(meshoptBounds.cone_axis.0, meshoptBounds.cone_axis.1, meshoptBounds.cone_axis.2), coneCutoff: meshoptBounds.cone_cutoff, coneAxisS8: PackedVector3(meshoptBounds.cone_axis_s8.0, meshoptBounds.cone_axis_s8.1, meshoptBounds.cone_axis_s8.2), coneCutoffS8: meshoptBounds.cone_cutoff_s8)
    }
    
    public func bounds<C: Collection>(for indices: C) -> Bounds where C.Element == UInt32 {
        let meshoptBounds = geometry.positions.withContents(as: Float.self) { positions in
            return indices.withContiguousStorageIfAvailable { indices in
                meshopt_computeClusterBounds(indices.baseAddress, indices.count, positions.baseAddress!, geometry.positions.count, geometry.positions.stride)
            }!
        }
        return Bounds(sphere: .init(centre: SIMD3(meshoptBounds.center.0, meshoptBounds.center.1, meshoptBounds.center.2), radius: meshoptBounds.radius), coneApex: PackedVector3(meshoptBounds.cone_apex.0, meshoptBounds.cone_apex.1, meshoptBounds.cone_apex.2), coneAxis: PackedVector3(meshoptBounds.cone_axis.0, meshoptBounds.cone_axis.1, meshoptBounds.cone_axis.2), coneCutoff: meshoptBounds.cone_cutoff, coneAxisS8: PackedVector3(meshoptBounds.cone_axis_s8.0, meshoptBounds.cone_axis_s8.1, meshoptBounds.cone_axis_s8.2), coneCutoffS8: meshoptBounds.cone_cutoff_s8)
    }
}

extension GeometryStreams {
    
    public func meshletCountBound(maxVerticesPerMeshlet: Int, maxTrianglesPerMeshlet: Int) -> Int {
        precondition(maxVerticesPerMeshlet <= 255, "The maximum vertices per meshlet must be less than 256.")
        precondition(maxTrianglesPerMeshlet <= 512, "The maximum triangles per meshlet must be no more than 512.")
        return meshopt_buildMeshletsBound(self.triangleIndices.count * 3, maxVerticesPerMeshlet, maxTrianglesPerMeshlet)
    }
    
    public func buildMeshlets(maxVerticesPerMeshlet: Int, maxTrianglesPerMeshlet: Int, coneWeight: Float) -> MeshletGeometry {
        let maxMeshlets = self.meshletCountBound(maxVerticesPerMeshlet: maxVerticesPerMeshlet, maxTrianglesPerMeshlet: maxTrianglesPerMeshlet)
        let inputIndices = self.triangleIndicesArray
        
        var meshletVertices: [UInt32] = []
        var meshletTriangles: [UInt8] = []
        let meshlets: [MeshletGeometry.Meshlet] = .init(unsafeUninitializedCapacity: maxMeshlets) { meshletBuffer, meshletCount in
            meshletVertices = .init(unsafeUninitializedCapacity: maxMeshlets * maxVerticesPerMeshlet, initializingWith: { verticesBuffer, verticesCount in
                meshletTriangles = .init(unsafeUninitializedCapacity: maxMeshlets * maxTrianglesPerMeshlet * 3, initializingWith: { trianglesBuffer, trianglesCount in
                    self.positions.withContents(as: Float.self) { positions in
                        meshletCount = meshopt_buildMeshlets(UnsafeMutableRawPointer(meshletBuffer.baseAddress!).assumingMemoryBound(to: meshopt_Meshlet.self), verticesBuffer.baseAddress, trianglesBuffer.baseAddress, inputIndices, inputIndices.count, positions.baseAddress, self.positions.count, self.positions.stride, maxVerticesPerMeshlet, maxTrianglesPerMeshlet, coneWeight)
                        
                        trianglesCount = Int(meshletBuffer.last!.triangleOffset + meshletBuffer.last!.triangleCount)
                        verticesCount = Int(meshletBuffer.last!.vertexOffset + meshletBuffer.last!.vertexCount)
                    }
                })
            })
        }
        return MeshletGeometry(geometry: self, meshlets: meshlets, vertices: meshletVertices, triangles: meshletTriangles)
    }
    
    public func buildMeshletsScan(maxVerticesPerMeshlet: Int, maxTrianglesPerMeshlet: Int) -> MeshletGeometry {
        let maxMeshlets = self.meshletCountBound(maxVerticesPerMeshlet: maxVerticesPerMeshlet, maxTrianglesPerMeshlet: maxTrianglesPerMeshlet)
        let inputIndices = self.triangleIndicesArray
        
        var meshletVertices: [UInt32] = []
        var meshletTriangles: [UInt8] = []
        let meshlets: [MeshletGeometry.Meshlet] = .init(unsafeUninitializedCapacity: maxMeshlets) { meshletBuffer, meshletCount in
            meshletVertices = .init(unsafeUninitializedCapacity: maxMeshlets * maxVerticesPerMeshlet, initializingWith: { verticesBuffer, verticesCount in
                meshletTriangles = .init(unsafeUninitializedCapacity: maxMeshlets * maxTrianglesPerMeshlet * 3, initializingWith: { trianglesBuffer, trianglesCount in
                    self.positions.withContents(as: Float.self) { positions in
                        meshletCount = meshopt_buildMeshletsScan(UnsafeMutableRawPointer(meshletBuffer.baseAddress!).assumingMemoryBound(to: meshopt_Meshlet.self), verticesBuffer.baseAddress, trianglesBuffer.baseAddress, inputIndices, inputIndices.count, self.positions.count, maxVerticesPerMeshlet, maxTrianglesPerMeshlet)
                        
                        trianglesCount = Int(meshletBuffer.last!.triangleOffset + meshletBuffer.last!.triangleCount)
                        verticesCount = Int(meshletBuffer.last!.vertexOffset + meshletBuffer.last!.vertexCount)
                    }
                })
            })
        }
        return MeshletGeometry(geometry: self, meshlets: meshlets, vertices: meshletVertices, triangles: meshletTriangles)
    }
}


#endif // canImport(MeshOptimizer
