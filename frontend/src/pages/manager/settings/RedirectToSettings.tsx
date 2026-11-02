import { Navigate, useParams } from "react-router";
import { paths } from "../../../paths";

/** Old in-app links to the chat tab, which was folded into Settings > General. */
export function RedirectToSettings() {
  const { id = "" } = useParams();
  return <Navigate to={paths.editStandup(id)} replace />;
}
