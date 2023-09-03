//
//  GeometryStreams+Assimp.swift
//  
//
//  Created by Thomas Roughton on 17/02/22.
//

#if canImport(CAssimp)
import CAssimp
import Foundation
import SubstrateMath

extension SIMD3<Float> {
    @inlinable
    public init(_ aiVector: aiVector3D) {
        self.init(aiVector.x, aiVector.y, aiVector.z)
    }
}

extension GeometryStreams {
    public init(assimpMesh mesh: aiMesh) {
        let vertexCount = Int(mesh.mNumVertices)
        
        self.init(vertexCount: vertexCount)
        self.makeStream(type: .positions, sizePerVertex: 3 * MemoryLayout<Float>.size, stridePerVertex: MemoryLayout<SIMD3<Float>>.stride)
        self.makeStream(type: .normals, sizePerVertex: 3 * MemoryLayout<Float>.size, stridePerVertex: MemoryLayout<SIMD3<Float>>.stride)
        
        
        self.indexStreams = []
        
        switch aiPrimitiveType(mesh.mPrimitiveTypes) {
        case aiPrimitiveType_POINT:
            let indexCount = Int(mesh.mNumFaces)
            let indices = [UInt32](unsafeUninitializedCapacity: indexCount) { indices, initializedCount in
                initializedCount = indexCount
                
                for faceNum in 0..<Int(mesh.mNumFaces) {
                    let face = mesh.mFaces[faceNum]
                    assert(face.mNumIndices == 1, "The faces must be points.")
                    
                    let index0 = UInt32(truncatingIfNeeded: face.mIndices[0])
                    indices.baseAddress!.advanced(by: faceNum).initialize(to: index0)
                }
            }
            
            self.indexStreams = [.init(primitiveType: .point, indices: indices)]
            
        case aiPrimitiveType_LINE:
            let indexCount = Int(mesh.mNumFaces * 2)
            let indices = [UInt32](unsafeUninitializedCapacity: indexCount) { indices, initializedCount in
                initializedCount = indexCount
                
                for faceNum in 0..<Int(mesh.mNumFaces) {
                    let face = mesh.mFaces[faceNum]
                    assert(face.mNumIndices == 2, "The faces must be lines.")
                    
                    let index0 = UInt32(truncatingIfNeeded: face.mIndices[0])
                    let index1 = UInt32(truncatingIfNeeded: face.mIndices[1])
                    indices.baseAddress!.advanced(by: 2 * faceNum + 0).initialize(to: index0)
                    indices.baseAddress!.advanced(by: 2 * faceNum + 1).initialize(to: index1)
                }
            }
            
            self.indexStreams = [.init(primitiveType: .line, indices: indices)]
            
        case aiPrimitiveType_TRIANGLE:
            let indexCount = Int(mesh.mNumFaces * 3)
            let indices = [UInt32](unsafeUninitializedCapacity: indexCount) { indices, initializedCount in
                initializedCount = indexCount
                
                for faceNum in 0..<Int(mesh.mNumFaces) {
                    let face = mesh.mFaces[faceNum]
                    assert(face.mNumIndices == 3, "The faces must be triangulated.")
                    
                    let index0 = UInt32(truncatingIfNeeded: face.mIndices[0])
                    let index1 = UInt32(truncatingIfNeeded: face.mIndices[1])
                    let index2 = UInt32(truncatingIfNeeded: face.mIndices[2])
                    
                    indices.baseAddress!.advanced(by: 3 * faceNum + 0).initialize(to: index0)
                    indices.baseAddress!.advanced(by: 3 * faceNum + 1).initialize(to: index1)
                    indices.baseAddress!.advanced(by: 3 * faceNum + 2).initialize(to: index2)
                }
            }
            
            self.indexStreams = [.init(primitiveType: .triangle, indices: indices)]
            
        default:
            var pointIndices = [UInt32]()
            var lineIndices = [UInt32]()
            var triangleIndices = [UInt32]()
            
            for faceNum in 0..<Int(mesh.mNumFaces) {
                let face = mesh.mFaces[faceNum]
                
                switch face.mNumIndices {
                case 1:
                    let index0 = UInt32(truncatingIfNeeded: face.mIndices[0])
                    pointIndices.append(index0)
                    
                case 2:
                    let index0 = UInt32(truncatingIfNeeded: face.mIndices[0])
                    let index1 = UInt32(truncatingIfNeeded: face.mIndices[1])
                    lineIndices.append(index0)
                    lineIndices.append(index1)
                    
                case 3:
                    let index0 = UInt32(truncatingIfNeeded: face.mIndices[0])
                    let index1 = UInt32(truncatingIfNeeded: face.mIndices[1])
                    let index2 = UInt32(truncatingIfNeeded: face.mIndices[2])
                    triangleIndices.append(index0)
                    triangleIndices.append(index1)
                    triangleIndices.append(index2)
                    
                default:
                    break
                }
            }
            
            if !pointIndices.isEmpty {
                self.indexStreams.append(.init(primitiveType: .point, indices: pointIndices))
            }
            
            if !lineIndices.isEmpty {
                self.indexStreams.append(.init(primitiveType: .line, indices: lineIndices))
            }
            
            if !triangleIndices.isEmpty {
                self.indexStreams.append(.init(primitiveType: .triangle, indices: triangleIndices))
            }
        }
        
        self.positions.withMutableContents(as: SIMD3<Float>.self, perform: { outPositions in
            for i in 0..<vertexCount {
                outPositions.baseAddress!.advanced(by: i).initialize(to: .init(mesh.mVertices[i]))
            }
        })
        
        self.normals!.withMutableContents(as: SIMD3<Float>.self, perform: { outNormals in
            for i in 0..<vertexCount {
                outNormals.baseAddress!.advanced(by: i).initialize(to: .init(mesh.mNormals[i]))
            }
        })
        
        if let tangents = mesh.mTangents {
            self.makeStream(type: .tangents, sizePerVertex: 3 * MemoryLayout<Float>.size, stridePerVertex: MemoryLayout<SIMD3<Float>>.stride)
            
            self.tangents!.withMutableContents(as: SIMD3<Float>.self, perform: { outTangents in
                for i in 0..<vertexCount {
                    outTangents.baseAddress!.advanced(by: i).initialize(to: .init(tangents[i]))
                }
            })
        }
        
        if let bitangents = mesh.mBitangents {
            self.makeStream(type: .bitangents, sizePerVertex: 3 * MemoryLayout<Float>.size, stridePerVertex: MemoryLayout<SIMD3<Float>>.stride)
            
            self[.bitangents]!.withMutableContents(as: SIMD3<Float>.self, perform: { outBitangents in
                for i in 0..<vertexCount {
                    outBitangents.baseAddress!.advanced(by: i).initialize(to: .init(bitangents[i]))
                }
            })
        }
        
        withUnsafeBytes(of: mesh.mTextureCoords) { texCoordArrays in
            let texCoordArrays = texCoordArrays.bindMemory(to: UnsafeMutablePointer<aiVector3D>?.self)
            
            withUnsafeBytes(of: mesh.mNumUVComponents) { uvComponentCounts in
                let uvComponentCounts = uvComponentCounts.bindMemory(to: UInt32.self)
                
                for i in 0..<Int(AI_MAX_NUMBER_OF_TEXTURECOORDS) {
                    guard let array = texCoordArrays[i] else { continue }
                    let channel = StreamType.texCoords(index: i)
                    
                    let componentCount = Int(uvComponentCounts[i])
                    
                    let stride = componentCount * MemoryLayout<Float>.size
                    self.makeStream(type: channel, sizePerVertex: stride, stridePerVertex: stride)
                    
                    self[channel]!.withUnsafeMutableBytes { outBuffer in
                        for i in 0..<vertexCount {
                            for c in 0..<componentCount {
                                outBuffer.storeBytes(of: SIMD3(array[i])[c], toByteOffset: i * stride + c * MemoryLayout<Float>.stride, as: Float.self)
                            }
                        }
                    }
                }
            }
        }
        
        withUnsafeBytes(of: mesh.mColors) { colorArrays in
            let colorArrays = colorArrays.bindMemory(to: UnsafeMutablePointer<aiColor4D>?.self)
            
            for i in 0..<Int(AI_MAX_NUMBER_OF_COLOR_SETS) {
                guard let array = colorArrays[i] else { continue }
                let channel = StreamType.vertexColors(index: i)
                
                let stride = MemoryLayout<SIMD4<Float>>.size
                self.makeStream(type: channel, sizePerVertex: stride, stridePerVertex: stride)
                
                self[channel]!.withMutableContents(as: SIMD4<Float>.self, perform: { outBuffer in
                    for i in 0..<vertexCount {
                        outBuffer[i] = SIMD4(array[i].r, array[i].g, array[i].b, array[i].a)
                    }
                })
            }
        }
        
        if mesh.mNumBones > 0 {
            self.boneIndicesAndWeights = .init(repeating: [], count: vertexCount)
            
            // Ordered per-vertex, then per-bone.
            for boneNum in 0..<mesh.mNumBones {
                let bone = mesh.mBones[Int(boneNum)]!
                
                for weightNum in 0..<Int(bone.pointee.mNumWeights) {
                    let weight = bone.pointee.mWeights[weightNum];
                    self.boneIndicesAndWeights![Int(weight.mVertexId)].append(VertexBone(boneIndex: boneNum, weight: weight.mWeight))
                }
                
            }
        }
    }
}


#endif // canImport(CAssimp)
