// internal/utils/union_find.go
package utils

import "go-tower-defense/internal/types"

// UnionFind is a data structure for finding connected components.
type UnionFind struct {
	parent map[types.EntityID]types.EntityID
	rank   map[types.EntityID]int
}

// NewUnionFind creates a new UnionFind structure.
func NewUnionFind() *UnionFind {
	return &UnionFind{
		parent: make(map[types.EntityID]types.EntityID),
		rank:   make(map[types.EntityID]int),
	}
}

// Find finds the root of the set containing id.
func (uf *UnionFind) Find(id types.EntityID) types.EntityID {
	if _, exists := uf.parent[id]; !exists {
		uf.parent[id] = id
		uf.rank[id] = 0
	}
	if uf.parent[id] != id {
		uf.parent[id] = uf.Find(uf.parent[id]) // Path compression
	}
	return uf.parent[id]
}

// Union merges the sets containing idA and idB.
func (uf *UnionFind) Union(idA, idB types.EntityID) {
	rootA := uf.Find(idA)
	rootB := uf.Find(idB)
	if rootA == rootB {
		return
	}
	if uf.rank[rootA] < uf.rank[rootB] {
		uf.parent[rootA] = rootB
	} else if uf.rank[rootA] > uf.rank[rootB] {
		uf.parent[rootB] = rootA
	} else {
		uf.parent[rootB] = rootA
		uf.rank[rootA]++
	}
}
