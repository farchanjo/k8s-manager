// DDD role: ValueObject
// Bounded context: metrics_observability
// Represents a PromQL query request and its possible result shapes.

package metrics_observability

// Time range for range queries.
#TimeRange: {
	// RFC 3339 start timestamp.
	start_rfc3339: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// RFC 3339 end timestamp.
	end_rfc3339: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// Query resolution step in seconds. Must be at least 1.
	step_seconds: int & >=1
}

// A PromQL query, either instant or range.
// Exactly one of (instant == true) or (range != _|_) must hold.
#PromQuery: {
	// PromQL expression to evaluate.
	expr: string & !=""

	// When true, the query is submitted to /api/v1/query (instant vector).
	// When false, a range definition must be provided.
	instant: bool

	// Range definition. Present when instant == false.
	range?: #TimeRange

	// Optional label selector to restrict the query scope.
	// Keys and values are plain strings; the client appends them to the expr
	// as additional label matchers where appropriate.
	label_selector?: {[string]: string}
}

// ---- Result discriminated union ----

// A single sample from an instant vector result.
#Sample: {
	// Metric labels for this sample.
	metric: {[string]: string}

	// Unix timestamp (seconds, fractional).
	timestamp_unix: float64

	// Numeric value of the sample.
	value: float64
}

// A single data point from a range matrix series.
#Point: {
	// Unix timestamp (seconds, fractional).
	t_unix: float64

	// Numeric value at this timestamp.
	v: float64
}

// One labeled series from a range matrix result.
#Series: {
	// Metric labels for this series.
	metric: {[string]: string}

	// Ordered list of (timestamp, value) pairs.
	points: [...#Point]
}

// Result of an instant query (resultType == "vector").
#InstantVectorResult: {
	result_type: "vector"
	samples: [...#Sample]
}

// Result of a range query (resultType == "matrix").
#RangeMatrixResult: {
	result_type: "matrix"
	series: [...#Series]
}

// Result of a scalar query (resultType == "scalar").
#ScalarResult: {
	result_type: "scalar"
	timestamp_unix: float64
	value: float64
}

// Result of a string query (resultType == "string").
#StringResult: {
	result_type: "string"
	value: string
}

// Discriminated union of all possible Prometheus query result shapes.
#PromQueryResult: #InstantVectorResult | #RangeMatrixResult | #ScalarResult | #StringResult
