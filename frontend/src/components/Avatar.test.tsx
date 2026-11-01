import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Avatar } from "./Avatar";
import { AvatarStack } from "./AvatarStack";
import { AVATAR_PALETTE, avatarColors, initialsFor } from "./avatarColors";

describe("initialsFor", () => {
  it("matches UiHelper#initials_for", () => {
    expect(initialsFor("Jane Q. Doe")).toBe("JD");
    expect(initialsFor("jane")).toBe("JA");
    expect(initialsFor("Émile Zola")).toBe("ÉZ");
    expect(initialsFor("  ")).toBe("?");
    expect(initialsFor(null)).toBe("?");
  });

  it("picks a palette entry from the byte sum of the name", () => {
    // "Ada": 65 + 100 + 97 = 262; 262 % 8 = 6
    expect(avatarColors("Ada")).toEqual(AVATAR_PALETTE[6]);
    expect(avatarColors("Ada")).toEqual(avatarColors("Ada"));
  });
});

describe("Avatar", () => {
  it("shows initials with a photo on top", () => {
    const { container } = render(<Avatar name="Jane Doe" src="https://avatars.example.com/jane.png" />);
    expect(screen.getByTestId("avatar")).toHaveTextContent("JD");
    expect(container.querySelector("img")).toHaveAttribute("src", "https://avatars.example.com/jane.png");
  });

  it("falls back to initials when the photo fails to load", () => {
    const { container } = render(<Avatar name="Jane Doe" src="https://avatars.example.com/broken.png" />);
    fireEvent.error(container.querySelector("img")!);
    expect(container.querySelector("img")).toBeNull();
    expect(screen.getByTestId("avatar")).toHaveTextContent("JD");
  });

  it("ignores non-https photo URLs", () => {
    const { container } = render(<Avatar name="Jane Doe" src="javascript:alert(1)" />);
    expect(container.querySelector("img")).toBeNull();
  });
});

describe("AvatarStack", () => {
  it("shows up to the limit and a +N count", () => {
    render(<AvatarStack people={["Ann Lee", "Bob Ray", "Cy Dee", { name: "Di Ho", avatar_url: null }]} limit={2} />);
    expect(screen.getAllByTestId("avatar")).toHaveLength(2);
    expect(screen.getByText("+2")).toBeInTheDocument();
    expect(screen.getByRole("img", { name: "Ann Lee, Bob Ray, Cy Dee and Di Ho" })).toBeInTheDocument();
  });
});
