{{/*
Reusable Deployment renderer for kodus app components.

Usage:
  {{- include "kodus.workload" (dict "ctx" . "name" "api" "component" .Values.api "exposes" true) }}

Inputs:
  ctx:        the root context (.)
  name:       short component name (api, worker, web, webhooks, mcp-manager, ast)
  component:  the values block for that component (.Values.api, etc.)
  exposes:    boolean — whether this workload listens on a port (api/web/webhooks/mcp/ast)
*/}}
{{- define "kodus.workload" -}}
{{- $ctx := .ctx -}}
{{- $name := .name -}}
{{- $c := .component -}}
{{- $exposes := .exposes -}}
{{- $fullName := printf "%s-%s" (include "kodus.fullname" $ctx) $name -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $fullName }}
  labels:
    {{- include "kodus.componentLabels" (dict "ctx" $ctx "component" $name) | nindent 4 }}
spec:
  replicas: {{ default 1 $c.replicaCount }}
  strategy:
    type: RollingUpdate
  selector:
    matchLabels:
      {{- include "kodus.componentSelectorLabels" (dict "ctx" $ctx "component" $name) | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "kodus.componentLabels" (dict "ctx" $ctx "component" $name) | nindent 8 }}
        {{- with $c.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      annotations:
        checksum/config: {{ include (print $ctx.Template.BasePath "/configmap-env.yaml") $ctx | sha256sum }}
        checksum/secret: {{ include (print $ctx.Template.BasePath "/secret-env.yaml") $ctx | sha256sum }}
        {{- with $c.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      serviceAccountName: {{ include "kodus.serviceAccountName" $ctx }}
      {{- with $ctx.Values.global.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- $waitFor := list -}}
      {{- if $ctx.Values.postgresql.enabled -}}{{ $waitFor = append $waitFor (printf "postgres %s %v" (include "kodus.postgres.serviceName" $ctx) $ctx.Values.postgresql.service.port) }}{{- end -}}
      {{- if $ctx.Values.mongodb.enabled -}}{{ $waitFor = append $waitFor (printf "mongodb %s %v" (include "kodus.mongodb.serviceName" $ctx) $ctx.Values.mongodb.service.port) }}{{- end -}}
      {{- if $ctx.Values.rabbitmq.enabled -}}{{ $waitFor = append $waitFor (printf "rabbitmq %s %v" (include "kodus.rabbitmq.serviceName" $ctx) $ctx.Values.rabbitmq.service.amqpPort) }}{{- end -}}
      {{- if $waitFor }}
      initContainers:
        - name: wait-for-deps
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              set -e
              for entry in {{- range $waitFor }} "{{ . }}" {{- end }}; do
                set -- $entry
                svc="$1"; host="$2"; port="$3"
                echo "Waiting for $svc at $host:$port..."
                until nc -z "$host" "$port" 2>/dev/null; do sleep 2; done
                echo "  $svc ready."
              done
              echo "All dependencies ready."
      {{- end }}
      containers:
        - name: {{ $name }}
          image: {{ include "kodus.image" (dict "ctx" $ctx "component" $c) }}
          imagePullPolicy: {{ include "kodus.imagePullPolicy" (dict "ctx" $ctx "component" $c) }}
          envFrom:
            {{- include "kodus.envFrom" $ctx | nindent 12 }}
            {{- with $c.extraEnvFrom }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- with $c.extraEnv }}
          env:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if $exposes }}
          ports:
            - name: http
              containerPort: {{ $c.containerPort }}
              protocol: TCP
          {{- end }}
          {{- with $c.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $c.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $c.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- with $c.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $c.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $c.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}

{{/*
Reusable ClusterIP Service for components that listen on HTTP/TCP.
*/}}
{{- define "kodus.workloadService" -}}
{{- $ctx := .ctx -}}
{{- $name := .name -}}
{{- $c := .component -}}
{{- $fullName := printf "%s-%s" (include "kodus.fullname" $ctx) $name -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ $fullName }}
  labels:
    {{- include "kodus.componentLabels" (dict "ctx" $ctx "component" $name) | nindent 4 }}
  {{- with $c.service.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ default "ClusterIP" $c.service.type }}
  {{- with $c.service.loadBalancerClass }}
  loadBalancerClass: {{ . }}
  {{- end }}
  ports:
    - name: http
      port: {{ $c.service.port }}
      targetPort: {{ $c.containerPort }}
      protocol: TCP
  selector:
    {{- include "kodus.componentSelectorLabels" (dict "ctx" $ctx "component" $name) | nindent 4 }}
{{- end -}}
