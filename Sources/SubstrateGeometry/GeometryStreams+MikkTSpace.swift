//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/01/23.
//

#if canImport(MikkTSpace)
import MikkTSpace
import SubstrateMath

extension GeometryStreams {
    
    static func withGeometry<T>(_ context: UnsafePointer<SMikkTSpaceContext>?, _ perform: (inout GeometryStreams) -> T) -> T {
        return perform(&context!.pointee.m_pUserData.assumingMemoryBound(to: GeometryStreams.self).pointee)
    }
    
    static let mikktInterface = SMikkTSpaceInterface(
        m_getNumFaces: { context in
            withGeometry(context) { geometry in
                return Int32(geometry.triangleIndices.count)
            }
        },
        m_getNumVerticesOfFace: { _, _ in
            return 3 // Always triangles
        },
        m_getPosition: { context, outVertex, faceIndex, vertexIndex in
            withGeometry(context) { geometry in
                let vertIndex = geometry.triangleIndices[Int(faceIndex)][Int(vertexIndex)]
                let pos = geometry.positions[Int(vertIndex), as: PackedVector3<Float>.self]
                outVertex![0] = pos.x
                outVertex![1] = pos.y
                outVertex![2] = pos.z
            }
        },
        m_getNormal: { context, outNormal, faceIndex, vertexIndex in
            withGeometry(context) { geometry in
                let vertIndex = geometry.triangleIndices[Int(faceIndex)][Int(vertexIndex)]
                let normal = geometry.normals![Int(vertIndex), as: PackedVector3<Float>.self]
                outNormal![0] = normal.x
                outNormal![1] = normal.y
                outNormal![2] = normal.z
            }
        },
        m_getTexCoord: { context, outTexCoord, faceIndex, vertexIndex in
            withGeometry(context) { geometry in
                let vertIndex = geometry.triangleIndices[Int(faceIndex)][Int(vertexIndex)]
                let texCoord = geometry[.texCoords(index: 0)]![Int(vertIndex), as: (x: Float, y: Float).self]
                outTexCoord![0] = texCoord.x
                outTexCoord![1] = texCoord.y
            }
        },
        m_setTSpaceBasic: { context, tangent, sign, faceIndex, vertexIndex in
            withGeometry(context) { geometry in
                let vertIndex = geometry.triangleIndices[Int(faceIndex)][Int(vertexIndex)]
                geometry.tangents![Int(vertIndex)] = SIMD4(tangent![0], tangent![1], tangent![2], sign > 0.0 ? 1.0 : -1.0)
            }
        },
        m_setTSpace: nil)
    
    /// Generates MikkTSpace-compliant tangents for all vertices from the vertex positions, normals, texture coordinates, and index buffers.
    public mutating func generateTangents() {
        if self.triangleIndices.count * 3 < self.positions.count {
            self.uniqueIndexBufferVertices()
        }
        if self.normals == nil {
            self.generateNormals()
        }
        
        
        self.tangents = .init(count: self.positions.count, size: MemoryLayout<SIMD4<Float>>.size, stride: MemoryLayout<SIMD4<Float>>.stride)
        
        if self[.texCoords(index: 0)] == nil {
            self.normals!.withContents(as: PackedVector3<Float>.self) { normals in
                for (i, normal) in normals.enumerated() {
                    let normal = SIMD3<Float>(normal)
                    if dot(normal, SIMD3(0, 1, 0)) > 0.99 {
                        self.tangents![i] = SIMD4(cross(normal, SIMD3(1, 0, 0)), 1)
                    } else {
                        self.tangents![i] = SIMD4(cross(normal, SIMD3(0, 1, 0)), 1)
                    }
                }
            }
            return
        }
        
        withUnsafePointer(to: Self.mikktInterface) { mikktInterface in
            withUnsafeMutablePointer(to: &self) {
                var context = SMikkTSpaceContext(m_pInterface: mikktInterface, m_pUserData: $0)
                MikkTSpace.genTangSpaceDefault(&context)
            }
        }
        
        self.deduplicateVertices()
    }
}

#endif // canImport(MikkTSpace)
