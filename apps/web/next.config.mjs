/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: ["@tp/shared"],
  experimental: {
    typedRoutes: false,
  },
};

export default nextConfig;
