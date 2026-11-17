package read

// Done is the state of a read that has finished: its value, and the wording of its
// failure ("" when it succeeded). A read that has not finished is the zero State.
func Done[T any](v T, errText string) State[T] {
	return State[T]{loaded: true, err: errText, v: v}
}

// Loaded reports whether the read has finished.
func (s State[T]) Loaded() bool { return s.loaded }

// Err is the wording of the read's failure, "" when it succeeded or has not finished.
func (s State[T]) Err() string { return s.err }

// Value is what the read read: the zero value when it failed or has not finished.
func (s State[T]) Value() T { return s.v }
