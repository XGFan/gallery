FROM node:lts-alpine AS web-builder
WORKDIR /app
COPY web/package*.json ./
RUN npm install
COPY web/ ./
RUN npm run build

#production stage
FROM docker.test4x.com/xgfan/saio-builder:20240411 AS go-builder
WORKDIR /app

COPY go.mod go.sum ./
ARG GOPROXY
RUN if [[ -z "$GOPROXY" ]] ; then echo GOPROXY not provided ; else export GOPROXY=$GOPROXY ; fi
RUN go mod download

COPY . ./
COPY --from=web-builder /app/dist /app/web/dist
WORKDIR /app/app

RUN GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -tags vips -o gallery .

FROM docker.test4x.com/xgfan/saio-base:20240311 AS runner
COPY --from=go-builder /app/gallery /app/gallery
USER root
WORKDIR /app/
EXPOSE 8000
ENTRYPOINT ["/app/gallery"]