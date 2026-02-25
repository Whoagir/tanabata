// pkg/utils/math.go
package utils

// Abs returns the absolute value of x.
func Abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

// Gcd computes the greatest common divisor of a and b.
func Gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
