// DDD role: ValueObject
package helm_management

// #ChartMetadata is an immutable value object that describes the Helm chart
// used to render a release revision. It is decoded from the "chart.metadata"
// field of the Helm release JSON embedded in the release Secret.
//
// #ChartMetadata corresponds to the chart.Metadata Go struct defined in
// https://github.com/helm/helm/blob/main/pkg/chart/metadata.go. Fields
// that Helm marks as optional may be absent in older charts.
//
// Equality is structural: two #ChartMetadata values are equal when every
// populated field is equal. The application uses (name, version) as the
// practical identity for display and grouping.
#ChartMetadata: {
	// name is the chart name as declared in Chart.yaml. Lowercase alphanumeric
	// with hyphens. Examples: "nginx", "cert-manager", "kube-prometheus-stack".
	name!: string

	// version is the chart version string. Must be a valid semantic version
	// (SemVer 2.0.0). Example: "1.2.3", "0.14.0-rc.1".
	version!: =~"^[0-9]+\\.[0-9]+\\.[0-9]"

	// appVersion is the version of the application that the chart installs.
	// Optional; not always present in library charts.
	appVersion?: string

	// apiVersion is the Chart.yaml schema version.
	// "v1" for Helm 2 charts; "v2" for Helm 3 charts.
	apiVersion!: "v1" | "v2"

	// description is the human-readable chart description from Chart.yaml.
	description?: string

	// type declares whether the chart is an application chart or a library
	// chart. Library charts may not have templates and cannot be installed
	// directly. Optional; defaults to "application" in the Helm spec.
	type?: "application" | "library"

	// icon is the URL of an icon image for display in the Helm Hub or chart
	// museum UIs. Optional.
	icon?: string

	// dependencies is the list of sub-charts that this chart depends on.
	// Populated from the "dependencies" field of Chart.yaml. May be empty.
	dependencies!: [...#ChartDependency]

	// maintainers is the list of maintainers declared in Chart.yaml.
	// May be empty.
	maintainers!: [...#Maintainer]

	// home is the URL of the chart's home page. Optional.
	home?: string

	// sources is the list of source code URLs associated with the chart.
	// May be empty.
	sources!: [...string]
}

// #ChartDependency describes a single dependency entry from a chart's
// Chart.yaml "dependencies" list. Dependencies are sub-charts that Helm
// resolves during "helm dependency update". In Phase 1, this struct is
// decoded from the embedded chart metadata in the release Secret and is
// read-only; K8sManager does not resolve or pull dependencies.
#ChartDependency: {
	// name is the dependency chart name.
	name!: string

	// version is the SemVer constraint string for the dependency.
	// Examples: ">=1.2.3", "~1.0", "1.x".
	version!: string

	// repository is the repository URL or OCI reference from which the
	// dependency should be pulled. Optional for bundled sub-charts.
	repository?: string

	// alias is an alternative name to give the chart in the parent chart's
	// template context. Optional.
	alias?: string

	// condition is a dotpath into the parent chart's values that, when set
	// to false, disables this dependency. Optional.
	condition?: string

	// tags is the list of tags associated with this dependency. Optional.
	// Used for conditional enabling/disabling of groups of dependencies.
	tags!: [...string]
}

// #Maintainer describes a single maintainer entry from Chart.yaml.
#Maintainer: {
	// name is the maintainer's display name.
	name!: string

	// email is the maintainer's email address. Optional.
	email?: string

	// url is the maintainer's web URL. Optional.
	url?: string
}
