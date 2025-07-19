extends Node

class_name LinearSolver






## Solves a system of linear equations Ax = b using Gaussian elimination with partial pivoting.
static func solve(A: Array, b: Array) -> Array:
	var n = b.size()
	if not (A.size() == n):
		print_matrix(A, "A on solve() fail")
		print_vector(b, "b on solve() fail")
		assert(false, "LinearSolver: Matrix A rows ({a_size}) does not match vector b size ({n_val}).".format({"a_size": A.size(), "n_val": n}))
	for row in A:
		if not (row.size() == n):
			print_matrix(A, "A on solve() fail")
			print_vector(b, "b on solve() fail")
			assert(false, "LinearSolver: Matrix A is not square (row size {row_sz} vs expected {n_val}).".format({"row_sz": row.size(), "n_val": n}))

	var A_copy = A.duplicate(true)
	var b_copy = b.duplicate()

	# --- Enhanced singularity/nan detection ---
	var matrix_norm = 0.0
	for i in range(n):
		for j in range(n):
			matrix_norm = max(matrix_norm, abs(A_copy[i][j]))

	for i in range(n):
		var pivot = abs(A_copy[i][i])
		var pivot_row = i
		for k in range(i + 1, n):
			if abs(A_copy[k][i]) > pivot:
				pivot = abs(A_copy[k][i])
				pivot_row = k

		if pivot_row != i:
			var temp_row = A_copy[i]
			A_copy[i] = A_copy[pivot_row]
			A_copy[pivot_row] = temp_row
			var temp_b = b_copy[i]
			b_copy[i] = b_copy[pivot_row]
			b_copy[pivot_row] = temp_b

		# Enhanced singularity/nan detection
		if not (!is_nan(A_copy[i][i]) and abs(A_copy[i][i]) >= max(1e-12, 1e-12 * matrix_norm)):
			print_matrix(A_copy, "A on pivot fail")
			print_vector(b_copy, "b on pivot fail")
			assert(false, "LinearSolver: Matrix is singular/invalid at pivots (row {step_i}). Pivot val: {p_val}".format({"step_i": i, "p_val": A_copy[i][i]}))

		for k in range(i + 1, n):
			var factor = A_copy[k][i] / A_copy[i][i]
			b_copy[k] -= factor * b_copy[i]
			A_copy[k][i] = 0.0 
			for j in range(i + 1, n):
				A_copy[k][j] -= factor * A_copy[i][j]

	var x = []
	x.resize(n)

	for i in range(n - 1, -1, -1): 
		if not (!is_nan(A_copy[i][i]) and abs(A_copy[i][i]) >= max(1e-12, 1e-12 * matrix_norm)):
			print_matrix(A_copy, "A on back-sub fail")
			print_vector(b_copy, "b on back-sub fail")
			assert(false, "LinearSolver: Matrix became singular/invalid during back substitution at row {row_i}. Pivot val: {p_val}".format({"row_i": i, "p_val": A_copy[i][i]}))

		var sum_ax = 0.0
		for j in range(i + 1, n):
			sum_ax += A_copy[i][j] * x[j]

		x[i] = (b_copy[i] - sum_ax) / A_copy[i][i]

	return x


## Utility function to print a matrix to the console for debugging.
static func print_matrix(M: Array, p_name: String = "Matrix"):
	print("--- {matrix_name} ---".format({"matrix_name": p_name}))
	if M.is_empty() or not M[0] is Array:
		print(M)
		return
	for row in M:
		var row_str = "[ "
		for val in row:
			if typeof(val) == TYPE_FLOAT:
				row_str += String.num(val, 3).lpad(8) + " "
			else:
				row_str += str(val).lpad(8) + " "
		row_str += "]"
		print(row_str)
	print("--------------")


## Utility function to print a vector to the console for debugging.
static func print_vector(V: Array, p_name: String = "Vector"):
	print("--- {vector_name} ---".format({"vector_name": p_name}))
	var vec_str = "[ "
	for val in V:
		if typeof(val) == TYPE_FLOAT:
			vec_str += String.num(val, 3).lpad(8) + " "
		else:
			vec_str += str(val).lpad(8) + " "
	vec_str += "]"
	print(vec_str)
	print("--------------")
