extends Node

class_name LinearSolver

## Solves a system of linear equations Ax = b using Gaussian elimination
## with partial pivoting.
## A: Array[Array[float]] - The coefficient matrix (NxN). Will be modified in place.
## b: Array[float] - The constant vector (Nx1). Will be modified in place.
## Returns: Array[float] - The solution vector x (Nx1), or an empty array if the matrix is singular.
static func solve(A: Array, b: Array) -> Array:
	var n = b.size()
	if A.size() != n:
		printerr("LinearSolver: Matrix A rows ({a_size}) does not match vector b size ({n_val}).".format({"a_size": A.size(), "n_val": n}))
		return []
	for row in A:
		if row.size() != n:
			printerr("LinearSolver: Matrix A is not square (row size {row_sz} vs expected {n_val}).".format({"row_sz": row.size(), "n_val": n}))
			return []

	# --- Forward Elimination with Partial Pivoting ---
	for i in range(n):
		# Find pivot row
		var pivot = abs(A[i][i])
		var pivot_row = i
		for k in range(i + 1, n):
			if abs(A[k][i]) > pivot:
				pivot = abs(A[k][i])
				pivot_row = k

		# Swap rows if necessary
		if pivot_row != i:
			# Swap rows in A
			var temp_row = A[i]
			A[i] = A[pivot_row]
			A[pivot_row] = temp_row
			# Swap corresponding elements in b
			var temp_b = b[i]
			b[i] = b[pivot_row]
			b[pivot_row] = temp_b

		# Check for singularity (or near-singularity)
		if abs(A[i][i]) < 1e-12: # Use a small tolerance instead of exact zero
			printerr("LinearSolver: Matrix is singular or near-singular at step {step_i}. Cannot solve.".format({"step_i": i}))
			# You could check if b[i] is also near-zero for infinite solutions,
			# but for circuit simulation, this usually indicates an error.
			return []

		# Eliminate column i in rows below row i
		for k in range(i + 1, n):
			var factor = A[k][i] / A[i][i]
			b[k] -= factor * b[i]
			A[k][i] = 0.0 # Explicitly set to zero after calculation
			for j in range(i + 1, n):
				A[k][j] -= factor * A[i][j]

	# --- Back Substitution ---
	var x = []
	x.resize(n) # Initialize solution vector

	for i in range(n - 1, -1, -1): # Iterate backwards from n-1 down to 0
		# Check for singularity again during back substitution (diagonal element is zero)
		if abs(A[i][i]) < 1e-12:
			printerr("LinearSolver: Matrix became singular during back substitution at row {row_i}.".format({"row_i": i}))
			return []

		var sum_ax = 0.0
		for j in range(i + 1, n):
			sum_ax += A[i][j] * x[j]

		x[i] = (b[i] - sum_ax) / A[i][i]

	return x

## Helper function to print a matrix (for debugging)
static func print_matrix(M: Array, name: String = "Matrix"):
	print("--- {matrix_name} ---".format({"matrix_name": name}))
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

## Helper function to print a vector (for debugging)
static func print_vector(V: Array, name: String = "Vector"):
	print("--- {vector_name} ---".format({"vector_name": name}))
	var vec_str = "[ "
	for val in V:
		if typeof(val) == TYPE_FLOAT:
			vec_str += String.num(val, 3).lpad(8) + " "
		else:
			vec_str += str(val).lpad(8) + " "
	vec_str += "]"
	print(vec_str)
	print("--------------")
