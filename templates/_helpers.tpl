{{/*
Expand the chart name.
*/}}
{{- define "kodus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a fully-qualified release name. Truncated to 63 chars per DNS-1123.
*/}}
{{- define "kodus.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "kodus.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "kodus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Selector labels for a specific component (api, worker, …).
*/}}
{{- define "kodus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kodus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Component-scoped name (e.g. release-kodus-api).
Usage: include "kodus.componentName" (dict "ctx" . "component" "api")
*/}}
{{- define "kodus.componentName" -}}
{{- printf "%s-%s" (include "kodus.fullname" .ctx) .component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Component selector labels.
Usage: include "kodus.componentSelectorLabels" (dict "ctx" . "component" "api")
*/}}
{{- define "kodus.componentSelectorLabels" -}}
{{ include "kodus.selectorLabels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Component labels (selector + common).
*/}}
{{- define "kodus.componentLabels" -}}
{{ include "kodus.labels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Service-account name to use.
*/}}
{{- define "kodus.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "kodus.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Resolved image reference for an app component.
Usage: include "kodus.image" (dict "ctx" . "component" .Values.api)
*/}}
{{- define "kodus.image" -}}
{{- $tag := default .ctx.Values.global.imageTag .component.image.tag -}}
{{- printf "%s:%s" .component.image.repository $tag -}}
{{- end -}}

{{- define "kodus.imagePullPolicy" -}}
{{- default .ctx.Values.global.imagePullPolicy .component.image.pullPolicy -}}
{{- end -}}

{{/*
Names of the central ConfigMap and Secret that hold the shared env-var bag.
*/}}
{{- define "kodus.envConfigMap" -}}
{{ include "kodus.fullname" . }}-env
{{- end -}}

{{- define "kodus.envSecret" -}}
{{ include "kodus.fullname" . }}-env
{{- end -}}

{{/*
Service hostnames (resolved inside the chart so we never hard-code release names).
*/}}
{{- define "kodus.api.serviceName" -}}{{ include "kodus.fullname" . }}-api{{- end -}}
{{- define "kodus.web.serviceName" -}}{{ include "kodus.fullname" . }}-web{{- end -}}
{{- define "kodus.webhooks.serviceName" -}}{{ include "kodus.fullname" . }}-webhooks{{- end -}}
{{- define "kodus.ast.serviceName" -}}{{ include "kodus.fullname" . }}-ast{{- end -}}
{{- define "kodus.mcpManager.serviceName" -}}{{ include "kodus.fullname" . }}-mcp-manager{{- end -}}
{{- define "kodus.postgres.serviceName" -}}{{ include "kodus.fullname" . }}-postgres{{- end -}}
{{- define "kodus.mongodb.serviceName" -}}{{ include "kodus.fullname" . }}-mongodb{{- end -}}
{{- define "kodus.rabbitmq.serviceName" -}}{{ include "kodus.fullname" . }}-rabbitmq{{- end -}}

{{/*
Resolve PG host/user/db considering the in-cluster postgres if enabled.
*/}}
{{- define "kodus.pg.host" -}}
{{- if .Values.postgresql.enabled -}}
{{ include "kodus.postgres.serviceName" . }}
{{- else -}}
{{ default "" .Values.config.API_PG_DB_HOST }}
{{- end -}}
{{- end -}}
{{- define "kodus.pg.username" -}}
{{- if .Values.postgresql.enabled -}}{{ .Values.postgresql.auth.username }}{{- else -}}{{ default "" .Values.config.API_PG_DB_USERNAME }}{{- end -}}
{{- end -}}
{{- define "kodus.pg.database" -}}
{{- if .Values.postgresql.enabled -}}{{ .Values.postgresql.auth.database }}{{- else -}}{{ default "" .Values.config.API_PG_DB_DATABASE }}{{- end -}}
{{- end -}}
{{- define "kodus.pg.port" -}}
{{- if .Values.postgresql.enabled -}}{{ .Values.postgresql.service.port }}{{- else -}}{{ default "5432" .Values.config.API_PG_DB_PORT }}{{- end -}}
{{- end -}}

{{- define "kodus.mg.host" -}}
{{- if .Values.mongodb.enabled -}}{{ include "kodus.mongodb.serviceName" . }}{{- else -}}{{ default "" .Values.config.API_MG_DB_HOST }}{{- end -}}
{{- end -}}
{{- define "kodus.mg.username" -}}
{{- if .Values.mongodb.enabled -}}{{ .Values.mongodb.auth.username }}{{- else -}}{{ default "" .Values.config.API_MG_DB_USERNAME }}{{- end -}}
{{- end -}}
{{- define "kodus.mg.database" -}}
{{- if .Values.mongodb.enabled -}}{{ .Values.mongodb.auth.database }}{{- else -}}{{ default "" .Values.config.API_MG_DB_DATABASE }}{{- end -}}
{{- end -}}
{{- define "kodus.mg.port" -}}
{{- if .Values.mongodb.enabled -}}{{ .Values.mongodb.service.port }}{{- else -}}{{ default "27017" .Values.config.API_MG_DB_PORT }}{{- end -}}
{{- end -}}

{{- define "kodus.mq.host" -}}
{{- if .Values.rabbitmq.enabled -}}{{ include "kodus.rabbitmq.serviceName" . }}{{- else -}}{{ default "" .Values.config.RABBITMQ_HOSTNAME }}{{- end -}}
{{- end -}}
{{- define "kodus.mq.username" -}}
{{- if .Values.rabbitmq.enabled -}}{{ .Values.rabbitmq.auth.username }}{{- else -}}{{ default "" .Values.secrets.RABBITMQ_DEFAULT_USER }}{{- end -}}
{{- end -}}
{{- define "kodus.mq.vhost" -}}
{{- if .Values.rabbitmq.enabled -}}{{ .Values.rabbitmq.auth.vhost }}{{- else -}}kodus-ai{{- end -}}
{{- end -}}

{{/*
Standard envFrom block referencing the central ConfigMap + Secret plus any
user-provided extras. Components include this in their pod spec.
*/}}
{{- define "kodus.envFrom" -}}
- configMapRef:
    name: {{ include "kodus.envConfigMap" . }}
- secretRef:
    name: {{ include "kodus.envSecret" . }}
{{- range .Values.extraExistingConfigMaps }}
- configMapRef:
    name: {{ . }}
{{- end }}
{{- range .Values.extraExistingSecrets }}
- secretRef:
    name: {{ . }}
{{- end }}
{{- end -}}
