// pkg/hexmap/pathfinding.go
package hexmap

import (
	"container/heap"
)

// AStar находит кратчайший путь от start до goal
func AStar(start, goal Hex, hm *HexMap) []Hex {
	pq := &PriorityQueue{}
	heap.Init(pq)
	heap.Push(pq, &Node{Hex: start, Cost: 0, Parent: nil})
	cameFrom := make(map[Hex]*Node)
	costSoFar := make(map[Hex]int)
	costSoFar[start] = 0
	for pq.Len() > 0 {
		current := heap.Pop(pq).(*Node)
		if current.Hex == goal {
			return reconstructPath(current)
		}
		for _, neighbor := range current.Hex.Neighbors(hm) {
			if !hm.IsPassable(neighbor) {
				continue
			}
			newCost := costSoFar[current.Hex] + 1
			if _, exists := costSoFar[neighbor]; !exists || newCost < costSoFar[neighbor] {
				costSoFar[neighbor] = newCost
				priority := newCost + neighbor.Distance(goal)
				heap.Push(pq, &Node{Hex: neighbor, Cost: priority, Parent: current})
				cameFrom[neighbor] = current
			}
		}
	}
	return nil // Нет пути
}

// PriorityQueue для A*
type PriorityQueue []*Node

type Node struct {
	Hex    Hex
	Cost   int
	Parent *Node
}

func (pq PriorityQueue) Len() int           { return len(pq) }
func (pq PriorityQueue) Less(i, j int) bool { return pq[i].Cost < pq[j].Cost }
func (pq PriorityQueue) Swap(i, j int)      { pq[i], pq[j] = pq[j], pq[i] }
func (pq *PriorityQueue) Push(x interface{}) {
	*pq = append(*pq, x.(*Node))
}
func (pq *PriorityQueue) Pop() interface{} {
	old := *pq
	n := len(old)
	item := old[n-1]
	*pq = old[0 : n-1]
	return item
}

func reconstructPath(node *Node) []Hex {
	path := []Hex{}
	for node != nil {
		path = append([]Hex{node.Hex}, path...)
		node = node.Parent
	}
	return path
}
