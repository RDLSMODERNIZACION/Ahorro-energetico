import { NextRequest, NextResponse } from "next/server";

const BACKEND = process.env.BACKEND_API_URL || "https://ahorro-energetico.onrender.com";

async function proxy(request: NextRequest) {
  const path = request.nextUrl.pathname.replace(/^\/api\/backend\/?/, "");
  const target = new URL(`${BACKEND}/${path}`);
  request.nextUrl.searchParams.forEach((value, key) => target.searchParams.append(key, value));

  const headers = new Headers();
  const authorization = request.headers.get("authorization");
  const contentType = request.headers.get("content-type");
  if (authorization) headers.set("authorization", authorization);
  if (contentType) headers.set("content-type", contentType);

  const method = request.method.toUpperCase();
  const body = method === "GET" || method === "HEAD" ? undefined : await request.arrayBuffer();
  const response = await fetch(target, { method, headers, body, cache: "no-store" });

  const responseHeaders = new Headers();
  const responseType = response.headers.get("content-type");
  if (responseType) responseHeaders.set("content-type", responseType);
  responseHeaders.set("cache-control", "no-store");

  return new NextResponse(response.body, {
    status: response.status,
    headers: responseHeaders,
  });
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
