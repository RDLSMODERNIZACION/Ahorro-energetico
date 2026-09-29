/** @type {import('next').NextConfig} */
const nextConfig = {
  basePath: "/ahorroenergetico",
  env: { NEXT_PUBLIC_BASE_PATH: "/ahorroenergetico" },
  async redirects() {
    return [
      { source: "/", destination: "/ahorroenergetico", basePath: false, permanent: false },
      { source: "/admin", destination: "/ahorroenergetico/admin", basePath: false, permanent: false },
    ];
  },
  typescript: {
    ignoreBuildErrors: true,
  },
};

export default nextConfig;
