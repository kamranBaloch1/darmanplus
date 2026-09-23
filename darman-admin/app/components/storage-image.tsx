"use client";

import Image from "next/image";

export default function StorageImage({
  src,
  alt = "",
  size = 128,
}: {
  src: string;
  alt?: string;
  size?: number;
}) {
  return (
    <Image
      src={src}
      alt={alt}
      width={size}
      height={size}
      sizes={`${size}px`}
      quality={72}
      loading="lazy"
    />
  );
}
